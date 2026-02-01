use std::path::PathBuf;
use std::sync::Arc;

use chrono::Utc;
use tauri::{AppHandle, Emitter};
use thiserror::Error;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tracing::{debug, error, info, warn};

use crate::models::{Task, TaskStatus};
use crate::notification::{NotificationManager, NotificationRequest, NotificationType};
use crate::protocol::{
    JsonRpcError, JsonRpcRequest, JsonRpcResponse, TaskEndParams, TaskEventPayload,
    TaskStartParams, TaskUpdateParams,
};
use crate::state::AppState;

/// Socket server errors
#[derive(Error, Debug)]
pub enum SocketServerError {
    #[error("Failed to bind socket: {0}")]
    BindFailed(String),

    #[error("Failed to cleanup socket file: {0}")]
    CleanupFailed(String),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("JSON parse error: {0}")]
    ParseError(String),

    #[error("JSON serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    #[error("Method not found: {0}")]
    MethodNotFound(String),

    #[error("Invalid parameters: {0}")]
    InvalidParams(String),

    #[error("Session not found: {0}")]
    SessionNotFound(String),

    #[error("Session already exists: {0}")]
    SessionAlreadyExists(String),

    #[error("Internal error: {0}")]
    InternalError(String),
}

impl From<SocketServerError> for JsonRpcError {
    fn from(err: SocketServerError) -> Self {
        match err {
            SocketServerError::ParseError(msg) => JsonRpcError::parse_error(&msg),
            SocketServerError::MethodNotFound(method) => JsonRpcError::method_not_found(&method),
            SocketServerError::InvalidParams(msg) => JsonRpcError::invalid_params(&msg),
            SocketServerError::SessionNotFound(id) => JsonRpcError::session_not_found(&id),
            SocketServerError::SessionAlreadyExists(id) => {
                JsonRpcError::session_already_exists(&id)
            }
            _ => JsonRpcError::internal_error(&err.to_string()),
        }
    }
}

/// Socket server configuration
pub struct SocketServerConfig {
    pub socket_path: PathBuf,
}

impl Default for SocketServerConfig {
    fn default() -> Self {
        Self {
            socket_path: PathBuf::from("/tmp/ai-agent-status.sock"),
        }
    }
}

/// Socket server
pub struct SocketServer {
    config: SocketServerConfig,
    app_handle: AppHandle,
    state: Arc<AppState>,
    notification_manager: Arc<NotificationManager>,
}

impl SocketServer {
    pub fn new(
        app_handle: AppHandle,
        state: Arc<AppState>,
        notification_manager: Arc<NotificationManager>,
        config: SocketServerConfig,
    ) -> Self {
        Self {
            config,
            app_handle,
            state,
            notification_manager,
        }
    }

    pub async fn run(self) -> Result<(), SocketServerError> {
        // Cleanup existing socket file
        self.cleanup_socket_file()?;

        // Bind UnixListener
        let listener = UnixListener::bind(&self.config.socket_path)
            .map_err(|e| SocketServerError::BindFailed(e.to_string()))?;

        // Set permissions (owner only)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(
                &self.config.socket_path,
                std::fs::Permissions::from_mode(0o600),
            )?;
        }

        info!(path = ?self.config.socket_path, "Socket server listening");

        // Accept connections loop
        loop {
            match listener.accept().await {
                Ok((stream, _addr)) => {
                    let handler = ConnectionHandler::new(
                        self.app_handle.clone(),
                        Arc::clone(&self.state),
                        Arc::clone(&self.notification_manager),
                    );

                    tokio::spawn(async move {
                        if let Err(e) = handler.handle(stream).await {
                            error!(error = ?e, "Connection handler error");
                        }
                    });
                }
                Err(e) => {
                    error!(error = ?e, "Accept error");
                    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                }
            }
        }
    }

    fn cleanup_socket_file(&self) -> Result<(), SocketServerError> {
        if self.config.socket_path.exists() {
            std::fs::remove_file(&self.config.socket_path)
                .map_err(|e| SocketServerError::CleanupFailed(e.to_string()))?;
        }
        Ok(())
    }
}

/// Connection handler for each client
struct ConnectionHandler {
    app_handle: AppHandle,
    state: Arc<AppState>,
    notification_manager: Arc<NotificationManager>,
}

impl ConnectionHandler {
    fn new(
        app_handle: AppHandle,
        state: Arc<AppState>,
        notification_manager: Arc<NotificationManager>,
    ) -> Self {
        Self {
            app_handle,
            state,
            notification_manager,
        }
    }

    async fn handle(self, stream: UnixStream) -> Result<(), SocketServerError> {
        let (reader, mut writer) = stream.into_split();
        let mut reader = BufReader::new(reader);
        let mut line = String::new();

        while reader.read_line(&mut line).await? > 0 {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                line.clear();
                continue;
            }

            let response = match self.process_message(trimmed).await {
                Ok(result) => result,
                Err(e) => JsonRpcResponse::error(None, e.into()),
            };

            let response_json = serde_json::to_string(&response)?;
            writer.write_all(response_json.as_bytes()).await?;
            writer.write_all(b"\n").await?;
            writer.flush().await?;

            line.clear();
        }

        Ok(())
    }

    async fn process_message(&self, message: &str) -> Result<JsonRpcResponse, SocketServerError> {
        debug!(message = %message, "Socket message received");
        let request: JsonRpcRequest = serde_json::from_str(message)
            .map_err(|e| SocketServerError::ParseError(e.to_string()))?;

        if request.jsonrpc != "2.0" {
            return Ok(JsonRpcResponse::error(
                request.id,
                JsonRpcError::invalid_request("Invalid JSON-RPC version"),
            ));
        }

        info!(
            method = %request.method,
            has_params = request.params.is_some(),
            "Socket request parsed"
        );

        let result = match request.method.as_str() {
            "task.start" => self.handle_task_start(&request).await,
            "task.update" => self.handle_task_update(&request).await,
            "task.end" => self.handle_task_end(&request).await,
            "ping" => self.handle_ping(&request).await,
            _ => Err(SocketServerError::MethodNotFound(request.method.clone())),
        };

        match result {
            Ok(value) => Ok(JsonRpcResponse::success(request.id, value)),
            Err(e) => Ok(JsonRpcResponse::error(request.id, e.into())),
        }
    }

    async fn handle_ping(
        &self,
        _request: &JsonRpcRequest,
    ) -> Result<serde_json::Value, SocketServerError> {
        Ok(serde_json::json!({
            "status": "pong",
            "timestamp": Utc::now().timestamp()
        }))
    }

    async fn handle_task_start(
        &self,
        request: &JsonRpcRequest,
    ) -> Result<serde_json::Value, SocketServerError> {
        let params: TaskStartParams = serde_json::from_value(
            request
                .params
                .clone()
                .ok_or_else(|| SocketServerError::InvalidParams("Missing params".to_string()))?,
        )
        .map_err(|e| SocketServerError::InvalidParams(e.to_string()))?;

        // Check if session already exists
        if self.state.get_task(&params.session_id).is_some() {
            return Err(SocketServerError::SessionAlreadyExists(
                params.session_id.clone(),
            ));
        }

        // Store task using handle_event
        let event = crate::models::AgentEvent::SessionStart {
            session_id: params.session_id.clone(),
            source: params.source.into(),
            cwd: params.project_path,
            description: params.description,
        };
        self.state.handle_event(event);

        // Emit event to frontend
        self.emit_tasks_updated()?;

        Ok(serde_json::json!({
            "status": "ok",
            "session_id": params.session_id
        }))
    }

    async fn handle_task_update(
        &self,
        request: &JsonRpcRequest,
    ) -> Result<serde_json::Value, SocketServerError> {
        let params: TaskUpdateParams = serde_json::from_value(
            request
                .params
                .clone()
                .ok_or_else(|| SocketServerError::InvalidParams("Missing params".to_string()))?,
        )
        .map_err(|e| SocketServerError::InvalidParams(e.to_string()))?;

        // Get task
        let task = self
            .state
            .get_task(&params.session_id)
            .ok_or_else(|| SocketServerError::SessionNotFound(params.session_id.clone()))?;

        // Update via event
        let status: TaskStatus = params.status.into();

        if status == TaskStatus::WaitingForInput {
            let event = crate::models::AgentEvent::WaitingForInput {
                session_id: params.session_id.clone(),
                message: params.description.clone().unwrap_or_default(),
            };
            self.state.handle_event(event);

            // Send notification
            self.send_notification(&task, NotificationType::WaitingForInput, params.description);
        } else if let Some(tool) = &params.current_tool {
            let event = crate::models::AgentEvent::ToolStart {
                session_id: params.session_id.clone(),
                tool_name: tool.clone(),
                description: params.description.clone(),
            };
            self.state.handle_event(event);
        }

        // Emit event to frontend
        self.emit_tasks_updated()?;

        Ok(serde_json::json!({
            "status": "ok",
            "session_id": params.session_id
        }))
    }

    async fn handle_task_end(
        &self,
        request: &JsonRpcRequest,
    ) -> Result<serde_json::Value, SocketServerError> {
        let params: TaskEndParams = serde_json::from_value(
            request
                .params
                .clone()
                .ok_or_else(|| SocketServerError::InvalidParams("Missing params".to_string()))?,
        )
        .map_err(|e| SocketServerError::InvalidParams(e.to_string()))?;

        // Get task before ending
        let task = self
            .state
            .get_task(&params.session_id)
            .ok_or_else(|| SocketServerError::SessionNotFound(params.session_id.clone()))?;

        // End session via event with status
        let status: TaskStatus = params.status.into();
        let event = crate::models::AgentEvent::SessionEnd {
            session_id: params.session_id.clone(),
            status: Some(status),
        };
        self.state.handle_event(event);

        // Emit event to frontend
        self.emit_tasks_updated()?;

        // Determine notification type and send
        let notification_type = match status {
            TaskStatus::Completed => NotificationType::TaskCompleted,
            TaskStatus::Error => NotificationType::TaskError,
            _ => NotificationType::TaskCompleted,
        };
        self.send_notification(&task, notification_type, None);

        // Cleanup rate limiter
        self.notification_manager
            .cleanup_session(&params.session_id);

        Ok(serde_json::json!({
            "status": "ok",
            "session_id": params.session_id
        }))
    }

    fn emit_tasks_updated(&self) -> Result<(), SocketServerError> {
        let tasks: Vec<TaskEventPayload> = self
            .state
            .get_all_tasks()
            .iter()
            .map(|t| TaskEventPayload {
                session_id: t.session_id.clone(),
                source: t.source.as_snake_case().to_string(),
                status: t.status.as_snake_case().to_string(),
                current_tool: t.current_tool.clone(),
                description: t.description.clone(),
                last_activity: t.last_activity.clone(),
                project_path: t.project_path.clone(),
                started_at: t.started_at.timestamp(),
                last_updated: t.last_updated.timestamp(),
            })
            .collect();

        self.app_handle
            .emit("tasks-updated", tasks)
            .map_err(|e| SocketServerError::InternalError(e.to_string()))?;

        Ok(())
    }

    fn send_notification(
        &self,
        task: &Task,
        notification_type: NotificationType,
        message: Option<String>,
    ) {
        let request = NotificationRequest {
            notification_type,
            source: task.source,
            session_id: task.session_id.clone(),
            project_path: task.project_path.clone(),
            message,
        };

        if let Err(e) = self
            .notification_manager
            .send_notification(&self.app_handle, request)
        {
            warn!(error = ?e, "Failed to send notification");
        }
    }
}
