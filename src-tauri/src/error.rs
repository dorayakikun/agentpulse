use thiserror::Error;

/// Application error type
#[allow(dead_code)]
#[derive(Debug, Error)]
pub enum AppError {
    #[error("Socket error: {0}")]
    Socket(#[from] std::io::Error),

    #[error("JSON parse error: {0}")]
    JsonParse(#[from] serde_json::Error),

    #[error("Task not found: {session_id}")]
    TaskNotFound { session_id: String },

    #[error("Invalid event: {message}")]
    InvalidEvent { message: String },

    #[error("Notification failed: {0}")]
    Notification(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

/// Result type for Tauri commands
#[allow(dead_code)]
pub type AppResult<T> = Result<T, AppError>;

/// JSON response for Tauri commands
impl serde::Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut state = serializer.serialize_struct("AppError", 2)?;
        state.serialize_field("code", &self.error_code())?;
        state.serialize_field("message", &self.to_string())?;
        state.end()
    }
}

impl AppError {
    /// Error code (for frontend handling)
    pub fn error_code(&self) -> &'static str {
        match self {
            AppError::Socket(_) => "SOCKET_ERROR",
            AppError::JsonParse(_) => "JSON_PARSE_ERROR",
            AppError::TaskNotFound { .. } => "TASK_NOT_FOUND",
            AppError::InvalidEvent { .. } => "INVALID_EVENT",
            AppError::Notification(_) => "NOTIFICATION_ERROR",
            AppError::Internal(_) => "INTERNAL_ERROR",
        }
    }

    /// Whether the error is recoverable
    #[allow(dead_code)]
    pub fn is_recoverable(&self) -> bool {
        match self {
            AppError::Socket(_) => true,
            AppError::JsonParse(_) => true,
            AppError::TaskNotFound { .. } => true,
            AppError::InvalidEvent { .. } => true,
            AppError::Notification(_) => false,
            AppError::Internal(_) => false,
        }
    }
}
