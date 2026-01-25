use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::models::{AgentSource, TaskStatus};

/// JSON-RPC Request
#[derive(Debug, Clone, Deserialize)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    pub method: String,
    #[serde(default)]
    pub params: Option<Value>,
    pub id: Option<Value>,
}

/// JSON-RPC Response
#[derive(Debug, Clone, Serialize)]
pub struct JsonRpcResponse {
    pub jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
    pub id: Option<Value>,
}

impl JsonRpcResponse {
    pub fn success(id: Option<Value>, result: Value) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            result: Some(result),
            error: None,
            id,
        }
    }

    pub fn error(id: Option<Value>, error: JsonRpcError) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            result: None,
            error: Some(error),
            id,
        }
    }
}

/// JSON-RPC Error
#[derive(Debug, Clone, Serialize)]
pub struct JsonRpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

impl JsonRpcError {
    pub fn parse_error(msg: &str) -> Self {
        Self {
            code: -32700,
            message: format!("Parse error: {}", msg),
            data: None,
        }
    }

    pub fn invalid_request(msg: &str) -> Self {
        Self {
            code: -32600,
            message: format!("Invalid Request: {}", msg),
            data: None,
        }
    }

    pub fn method_not_found(method: &str) -> Self {
        Self {
            code: -32601,
            message: format!("Method not found: {}", method),
            data: None,
        }
    }

    pub fn invalid_params(msg: &str) -> Self {
        Self {
            code: -32602,
            message: format!("Invalid params: {}", msg),
            data: None,
        }
    }

    pub fn internal_error(msg: &str) -> Self {
        Self {
            code: -32603,
            message: format!("Internal error: {}", msg),
            data: None,
        }
    }

    pub fn session_not_found(session_id: &str) -> Self {
        Self {
            code: -32001,
            message: format!("Session not found: {}", session_id),
            data: None,
        }
    }

    pub fn session_already_exists(session_id: &str) -> Self {
        Self {
            code: -32002,
            message: format!("Session already exists: {}", session_id),
            data: None,
        }
    }
}

/// Task start parameters
#[derive(Debug, Clone, Deserialize)]
pub struct TaskStartParams {
    pub session_id: String,
    pub source: AgentSourceParam,
    pub project_path: String,
    #[serde(default)]
    pub description: Option<String>,
}

/// Task update parameters
#[derive(Debug, Clone, Deserialize)]
pub struct TaskUpdateParams {
    pub session_id: String,
    pub status: TaskStatusParam,
    #[serde(default)]
    pub current_tool: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
}

/// Task end parameters
#[derive(Debug, Clone, Deserialize)]
pub struct TaskEndParams {
    pub session_id: String,
    pub status: TaskStatusParam,
    #[serde(default)]
    #[allow(dead_code)]
    pub description: Option<String>,
}

/// Agent source parameter (snake_case for JSON)
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentSourceParam {
    ClaudeCode,
    Codex,
}

impl From<AgentSourceParam> for AgentSource {
    fn from(param: AgentSourceParam) -> Self {
        match param {
            AgentSourceParam::ClaudeCode => AgentSource::ClaudeCode,
            AgentSourceParam::Codex => AgentSource::Codex,
        }
    }
}

/// Task status parameter (snake_case for JSON)
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatusParam {
    Running,
    WaitingForInput,
    Completed,
    Error,
}

impl From<TaskStatusParam> for TaskStatus {
    fn from(param: TaskStatusParam) -> Self {
        match param {
            TaskStatusParam::Running => TaskStatus::Running,
            TaskStatusParam::WaitingForInput => TaskStatus::WaitingForInput,
            TaskStatusParam::Completed => TaskStatus::Completed,
            TaskStatusParam::Error => TaskStatus::Error,
        }
    }
}

/// Task event payload for frontend
#[derive(Debug, Clone, Serialize)]
pub struct TaskEventPayload {
    pub session_id: String,
    pub source: String,
    pub status: String,
    pub current_tool: Option<String>,
    pub description: Option<String>,
    pub project_path: String,
    pub started_at: i64,
    pub last_updated: i64,
}

/// Notification payload
#[allow(dead_code)]
#[derive(Debug, Clone, Serialize)]
pub struct NotificationPayload {
    pub session_id: String,
    pub status: String,
    pub project_name: String,
}
