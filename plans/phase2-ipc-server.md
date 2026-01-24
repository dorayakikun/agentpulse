# Phase 2: IPC サーバー実装 - 詳細設計書

## 概要

Claude Code / Codex からのイベントを受信する Unix Domain Socket サーバーの実装設計。

## 1. socket_server.rs の詳細設計

### 1.1 構造体定義

```rust
// src-tauri/src/socket_server.rs

use std::path::PathBuf;
use std::sync::Arc;
use tokio::net::{UnixListener, UnixStream};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tauri::{AppHandle, Emitter};

use crate::models::{Task, TaskStatus, AgentSource};
use crate::state::AppState;

/// ソケットサーバーの設定
pub struct SocketServerConfig {
    pub socket_path: PathBuf,
    pub max_connections: usize,
    pub connection_timeout_secs: u64,
}

impl Default for SocketServerConfig {
    fn default() -> Self {
        Self {
            socket_path: PathBuf::from("/tmp/ai-agent-status.sock"),
            max_connections: 100,
            connection_timeout_secs: 30,
        }
    }
}

/// ソケットサーバー本体
pub struct SocketServer {
    config: SocketServerConfig,
    app_handle: AppHandle,
    state: Arc<AppState>,
}
```

### 1.2 ソケットリスナーの起動処理

```rust
impl SocketServer {
    pub fn new(app_handle: AppHandle, state: Arc<AppState>, config: SocketServerConfig) -> Self {
        Self { config, app_handle, state }
    }

    pub async fn run(self) -> Result<(), SocketServerError> {
        // 既存のソケットファイルを削除
        self.cleanup_socket_file()?;

        // UnixListener をバインド
        let listener = UnixListener::bind(&self.config.socket_path)
            .map_err(|e| SocketServerError::BindFailed(e.to_string()))?;

        // パーミッション設定 (owner only)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(
                &self.config.socket_path,
                std::fs::Permissions::from_mode(0o600),
            )?;
        }

        // 接続受付ループ
        loop {
            match listener.accept().await {
                Ok((stream, _addr)) => {
                    let handler = ConnectionHandler::new(
                        self.app_handle.clone(),
                        Arc::clone(&self.state),
                    );

                    tokio::spawn(async move {
                        if let Err(e) = handler.handle(stream).await {
                            log::error!("Connection handler error: {:?}", e);
                        }
                    });
                }
                Err(e) => {
                    log::error!("Accept error: {:?}", e);
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
```

### 1.3 クライアント接続のハンドリング

```rust
struct ConnectionHandler {
    app_handle: AppHandle,
    state: Arc<AppState>,
}

impl ConnectionHandler {
    fn new(app_handle: AppHandle, state: Arc<AppState>) -> Self {
        Self { app_handle, state }
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
        let request: JsonRpcRequest = serde_json::from_str(message)?;

        if request.jsonrpc != "2.0" {
            return Ok(JsonRpcResponse::error(
                request.id,
                JsonRpcError::invalid_request("Invalid JSON-RPC version"),
            ));
        }

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
}
```

### 1.4 エラーハンドリング

```rust
use thiserror::Error;

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

    #[error("Internal error: {0}")]
    InternalError(String),
}
```

---

## 2. JSON-RPC プロトコル仕様

### 2.1 リクエスト/レスポンス構造体

```rust
// src-tauri/src/protocol.rs

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Deserialize)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    pub method: String,
    #[serde(default)]
    pub params: Option<Value>,
    pub id: Option<Value>,
}

#[derive(Debug, Clone, Serialize)]
pub struct JsonRpcResponse {
    pub jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
    pub id: Option<Value>,
}

#[derive(Debug, Clone, Serialize)]
pub struct JsonRpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}
```

### 2.2 サポートするメソッド一覧

| メソッド | 説明 | パラメータ |
|----------|------|-----------|
| `task.start` | 新規セッション開始 | `TaskStartParams` |
| `task.update` | セッション状態更新 | `TaskUpdateParams` |
| `task.end` | セッション終了 | `TaskEndParams` |
| `ping` | ヘルスチェック | なし |

```rust
#[derive(Debug, Clone, Deserialize)]
pub struct TaskStartParams {
    pub session_id: String,
    pub source: AgentSourceParam,
    pub project_path: String,
    #[serde(default)]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TaskUpdateParams {
    pub session_id: String,
    pub status: TaskStatusParam,
    #[serde(default)]
    pub current_tool: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct TaskEndParams {
    pub session_id: String,
    pub status: TaskStatusParam,
    #[serde(default)]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentSourceParam {
    ClaudeCode,
    Codex,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatusParam {
    Running,
    WaitingForInput,
    Completed,
    Error,
}
```

### 2.3 エラーコード定義

| コード | 名前 | 説明 |
|--------|------|------|
| -32700 | Parse error | JSON パースエラー |
| -32600 | Invalid Request | 不正なリクエスト |
| -32601 | Method not found | メソッドが存在しない |
| -32602 | Invalid params | パラメータが不正 |
| -32603 | Internal error | 内部エラー |
| -32001 | Session not found | セッションが存在しない |
| -32002 | Session already exists | セッションが既に存在 |

---

## 3. イベント処理フロー

### 3.1 メソッドハンドラー

```rust
impl ConnectionHandler {
    async fn handle_task_start(&self, request: &JsonRpcRequest) -> Result<Value, SocketServerError> {
        let params: TaskStartParams = serde_json::from_value(
            request.params.clone().ok_or_else(|| {
                SocketServerError::InvalidParams("Missing params".to_string())
            })?
        )?;

        if self.state.tasks.contains_key(&params.session_id) {
            return Err(SocketServerError::InvalidParams(
                format!("Session {} already exists", params.session_id)
            ));
        }

        let now = std::time::SystemTime::now();
        let task = Task {
            session_id: params.session_id.clone(),
            source: params.source.into(),
            status: TaskStatus::Running,
            current_tool: None,
            description: params.description,
            project_path: params.project_path,
            started_at: now,
            last_updated: now,
        };

        self.state.tasks.insert(params.session_id.clone(), task.clone());
        self.emit_task_event("task:created", &task)?;

        Ok(serde_json::json!({ "status": "ok", "session_id": params.session_id }))
    }

    async fn handle_task_update(&self, request: &JsonRpcRequest) -> Result<Value, SocketServerError> {
        let params: TaskUpdateParams = serde_json::from_value(
            request.params.clone().ok_or_else(|| {
                SocketServerError::InvalidParams("Missing params".to_string())
            })?
        )?;

        let mut task = self.state.tasks.get_mut(&params.session_id)
            .ok_or_else(|| SocketServerError::SessionNotFound(params.session_id.clone()))?;

        task.status = params.status.into();
        task.last_updated = std::time::SystemTime::now();
        if let Some(tool) = params.current_tool { task.current_tool = Some(tool); }
        if let Some(desc) = params.description { task.description = Some(desc); }

        let updated_task = task.clone();
        drop(task);

        self.emit_task_event("task:updated", &updated_task)?;

        if updated_task.status == TaskStatus::WaitingForInput {
            self.trigger_notification(&updated_task)?;
        }

        Ok(serde_json::json!({ "status": "ok", "session_id": params.session_id }))
    }

    async fn handle_task_end(&self, request: &JsonRpcRequest) -> Result<Value, SocketServerError> {
        let params: TaskEndParams = serde_json::from_value(
            request.params.clone().ok_or_else(|| {
                SocketServerError::InvalidParams("Missing params".to_string())
            })?
        )?;

        let (_session_id, mut task) = self.state.tasks.remove(&params.session_id)
            .ok_or_else(|| SocketServerError::SessionNotFound(params.session_id.clone()))?;

        task.status = params.status.into();
        task.last_updated = std::time::SystemTime::now();
        if let Some(desc) = params.description { task.description = Some(desc); }

        self.emit_task_event("task:ended", &task)?;

        if task.status == TaskStatus::Completed || task.status == TaskStatus::Error {
            self.trigger_notification(&task)?;
        }

        Ok(serde_json::json!({ "status": "ok", "session_id": params.session_id }))
    }

    async fn handle_ping(&self, _request: &JsonRpcRequest) -> Result<Value, SocketServerError> {
        Ok(serde_json::json!({
            "status": "pong",
            "timestamp": std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH).unwrap().as_secs()
        }))
    }
}
```

### 3.2 Frontend への通知

```rust
#[derive(Debug, Clone, Serialize)]
pub struct TaskEventPayload {
    pub session_id: String,
    pub source: String,
    pub status: String,
    pub current_tool: Option<String>,
    pub description: Option<String>,
    pub project_path: String,
    pub started_at: u64,
    pub last_updated: u64,
}

impl ConnectionHandler {
    fn emit_task_event(&self, event_name: &str, task: &Task) -> Result<(), SocketServerError> {
        let payload = TaskEventPayload::from(task);
        self.app_handle.emit(event_name, payload)
            .map_err(|e| SocketServerError::InternalError(e.to_string()))?;
        Ok(())
    }

    fn trigger_notification(&self, task: &Task) -> Result<(), SocketServerError> {
        self.app_handle.emit("notification:trigger", NotificationPayload {
            session_id: task.session_id.clone(),
            status: task.status.clone(),
            project_name: task.project_path.split('/').last().unwrap_or("Unknown").to_string(),
        }).map_err(|e| SocketServerError::InternalError(e.to_string()))?;
        Ok(())
    }
}
```

---

## 4. Tauri との統合

### 4.1 lib.rs での起動

```rust
// src-tauri/src/lib.rs

use std::sync::Arc;
use tauri::{Manager, RunEvent};

mod models;
mod state;
mod socket_server;
mod protocol;

use state::AppState;
use socket_server::{SocketServer, SocketServerConfig};

pub fn run() {
    let app_state = Arc::new(AppState::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .manage(app_state.clone())
        .setup(move |app| {
            let app_handle = app.handle().clone();
            let state_clone = Arc::clone(&app_state);

            // バックグラウンドでソケットサーバーを起動
            tauri::async_runtime::spawn(async move {
                let config = SocketServerConfig::default();
                let server = SocketServer::new(app_handle, state_clone, config);
                if let Err(e) = server.run().await {
                    log::error!("Socket server error: {:?}", e);
                }
            });

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_app_handle, event| {
            if let RunEvent::Exit = event {
                // ソケットファイルのクリーンアップ
                let _ = std::fs::remove_file("/tmp/ai-agent-status.sock");
            }
        });
}
```

---

## 5. テスト戦略

### 5.1 ユニットテスト項目

- [ ] JSON-RPC リクエストのパース
- [ ] JSON-RPC レスポンスのシリアライズ
- [ ] エラーコードの正確性
- [ ] パラメータ構造体のデシリアライズ
- [ ] TaskEventPayload への変換

### 5.2 統合テスト用スクリプト

```bash
#!/bin/bash
# scripts/test_socket.sh

SOCKET="/tmp/ai-agent-status.sock"
SESSION_ID="test-session-$(date +%s)"

send_request() {
    local method="$1"
    local params="$2"
    echo "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" | nc -U "$SOCKET"
}

# テスト実行
echo "=== ping ===" && send_request "ping" "null"
echo "=== task.start ===" && send_request "task.start" "{\"session_id\":\"${SESSION_ID}\",\"source\":\"claude_code\",\"project_path\":\"/tmp/test\"}"
echo "=== task.update ===" && send_request "task.update" "{\"session_id\":\"${SESSION_ID}\",\"status\":\"waiting_for_input\"}"
echo "=== task.end ===" && send_request "task.end" "{\"session_id\":\"${SESSION_ID}\",\"status\":\"completed\"}"
```

---

## 6. 実装順序

### チェックリスト

```
□ 1. protocol.rs (新規)
  □ JsonRpcRequest / JsonRpcResponse
  □ JsonRpcError + エラーコード
  □ TaskStartParams / TaskUpdateParams / TaskEndParams
  □ AgentSourceParam / TaskStatusParam

□ 2. models.rs (更新)
  □ From<AgentSourceParam> for AgentSource
  □ From<TaskStatusParam> for TaskStatus

□ 3. socket_server.rs (新規)
  □ SocketServerConfig / SocketServer
  □ SocketServerError
  □ SocketServer::run()
  □ ConnectionHandler
  □ handle_ping / handle_task_start / handle_task_update / handle_task_end
  □ emit_task_event / trigger_notification
  □ ユニットテスト

□ 4. lib.rs (更新)
  □ mod protocol / mod socket_server
  □ setup() でソケットサーバー起動
  □ RunEvent::Exit でクリーンアップ

□ 5. scripts/test_socket.sh (新規)
  □ テスト用スクリプト

□ 6. Cargo.toml (更新)
  □ thiserror = "1"
  □ log = "0.4"
```

---

## 依存クレート

```toml
[dependencies]
tauri = { version = "2", features = [] }
tauri-plugin-notification = "2"
tokio = { version = "1", features = ["full", "net"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
dashmap = "5"
thiserror = "1"
log = "0.4"
```

---

## Critical Files

| ファイル | 役割 |
|----------|------|
| `src-tauri/src/socket_server.rs` | IPC サーバーのメインロジック |
| `src-tauri/src/protocol.rs` | JSON-RPC プロトコル型定義 |
| `src-tauri/src/lib.rs` | Tauri 統合、サーバー起動 |
| `src-tauri/src/state.rs` | タスク状態管理 |
| `scripts/test_socket.sh` | 手動テスト用スクリプト |
