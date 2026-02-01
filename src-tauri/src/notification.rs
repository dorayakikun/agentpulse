use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration, Instant};

use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;
use thiserror::Error;
use tracing::info;

use crate::models::{AgentSource, TaskStatus};

/// Notification type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum NotificationType {
    /// Task completed notification
    TaskCompleted,
    /// Waiting for input notification
    WaitingForInput,
    /// Error notification
    TaskError,
}

impl NotificationType {
    pub fn display_name(&self) -> &'static str {
        match self {
            NotificationType::TaskCompleted => "Task Completed",
            NotificationType::WaitingForInput => "Input Required",
            NotificationType::TaskError => "Task Error",
        }
    }
}

impl From<TaskStatus> for Option<NotificationType> {
    fn from(status: TaskStatus) -> Self {
        match status {
            TaskStatus::Completed => Some(NotificationType::TaskCompleted),
            TaskStatus::WaitingForInput => Some(NotificationType::WaitingForInput),
            TaskStatus::Error => Some(NotificationType::TaskError),
            TaskStatus::Running => None,
        }
    }
}

/// Notification request
#[derive(Debug, Clone)]
pub struct NotificationRequest {
    pub notification_type: NotificationType,
    pub source: AgentSource,
    pub session_id: String,
    pub project_path: String,
    pub message: Option<String>,
}

/// Notification error
#[derive(Error, Debug)]
pub enum NotificationError {
    #[error("Failed to send notification: {0}")]
    SendFailed(String),
    #[error("Rate limited")]
    RateLimited,
}

/// Rate limiter for notifications
struct NotificationRateLimiter {
    last_notification: RwLock<HashMap<(String, NotificationType), Instant>>,
    rate_limit_duration: Duration,
}

impl NotificationRateLimiter {
    fn new(rate_limit_seconds: u64) -> Self {
        Self {
            last_notification: RwLock::new(HashMap::new()),
            rate_limit_duration: Duration::from_secs(rate_limit_seconds),
        }
    }

    fn check_and_update(&self, session_id: &str, notification_type: NotificationType) -> bool {
        let now = Instant::now();

        // Check with read lock
        {
            let last_notifications = self.last_notification.read().unwrap();
            if let Some(last_time) =
                last_notifications.get(&(session_id.to_string(), notification_type))
            {
                if now.duration_since(*last_time) < self.rate_limit_duration {
                    return false;
                }
            }
        }

        // Update with write lock
        {
            let mut last_notifications = self.last_notification.write().unwrap();
            last_notifications.insert((session_id.to_string(), notification_type), now);
        }

        true
    }

    fn cleanup_session(&self, session_id: &str) {
        let mut last_notifications = self.last_notification.write().unwrap();
        last_notifications.retain(|(id, _), _| id != session_id);
    }
}

/// Notification manager
pub struct NotificationManager {
    rate_limiter: NotificationRateLimiter,
    enabled: RwLock<bool>,
}

impl Default for NotificationManager {
    fn default() -> Self {
        Self::new()
    }
}

impl NotificationManager {
    pub fn new() -> Self {
        Self {
            rate_limiter: NotificationRateLimiter::new(5),
            enabled: RwLock::new(true),
        }
    }

    pub fn send_notification(
        &self,
        app: &AppHandle,
        request: NotificationRequest,
    ) -> Result<(), NotificationError> {
        // Check if enabled
        if !*self.enabled.read().unwrap() {
            return Ok(());
        }

        // Check rate limit
        if !self
            .rate_limiter
            .check_and_update(&request.session_id, request.notification_type)
        {
            return Err(NotificationError::RateLimited);
        }

        let title = self.build_title(&request);
        let body = self.build_body(&request);

        app.notification()
            .builder()
            .title(&title)
            .body(&body)
            .show()
            .map_err(|e| NotificationError::SendFailed(e.to_string()))?;

        info!(
            source = %request.source,
            notification_type = request.notification_type.display_name(),
            session_id = %request.session_id,
            "Notification sent"
        );

        Ok(())
    }

    pub fn cleanup_session(&self, session_id: &str) {
        self.rate_limiter.cleanup_session(session_id);
    }

    fn build_title(&self, request: &NotificationRequest) -> String {
        let source_prefix = match request.source {
            AgentSource::ClaudeCode => "Claude Code",
            AgentSource::Codex => "Codex",
        };
        format!(
            "{} - {}",
            source_prefix,
            request.notification_type.display_name()
        )
    }

    fn build_body(&self, request: &NotificationRequest) -> String {
        let project_name = std::path::Path::new(&request.project_path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(&request.project_path);

        let base_message = match request.notification_type {
            NotificationType::TaskCompleted => format!("Task completed in {}", project_name),
            NotificationType::WaitingForInput => format!("Waiting for input in {}", project_name),
            NotificationType::TaskError => format!("Task error in {}", project_name),
        };

        match &request.message {
            Some(msg) if !msg.is_empty() => format!("{}\n{}", base_message, msg),
            _ => base_message,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rate_limiter() {
        let limiter = NotificationRateLimiter::new(1);
        assert!(limiter.check_and_update("session1", NotificationType::TaskCompleted));
        assert!(!limiter.check_and_update("session1", NotificationType::TaskCompleted)); // Rate limited
        assert!(limiter.check_and_update("session1", NotificationType::WaitingForInput)); // Different type is OK
        assert!(limiter.check_and_update("session2", NotificationType::TaskCompleted)); // Different session is OK
    }

    #[test]
    fn test_rate_limiter_cleanup() {
        let limiter = NotificationRateLimiter::new(60);
        limiter.check_and_update("session1", NotificationType::TaskCompleted);
        limiter.cleanup_session("session1");
        // After cleanup, should be able to send again (though still rate limited by time)
        assert!(limiter.check_and_update("session1", NotificationType::TaskCompleted));
    }
}
