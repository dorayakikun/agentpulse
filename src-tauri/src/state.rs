use crate::models::{AgentEvent, Task, TaskStatus};
use chrono::Utc;
use dashmap::DashMap;
use std::sync::Arc;

/// Application state
#[derive(Debug, Clone)]
pub struct AppState {
    tasks: Arc<DashMap<String, Task>>,
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

impl AppState {
    pub fn new() -> Self {
        Self {
            tasks: Arc::new(DashMap::new()),
        }
    }

    /// Get all tasks
    pub fn get_all_tasks(&self) -> Vec<Task> {
        self.tasks
            .iter()
            .map(|entry| entry.value().clone())
            .collect()
    }

    /// Get a task by session ID
    pub fn get_task(&self, session_id: &str) -> Option<Task> {
        self.tasks.get(session_id).map(|t| t.clone())
    }

    /// Handle an agent event
    pub fn handle_event(&self, event: AgentEvent) -> Option<Task> {
        match event {
            AgentEvent::SessionStart {
                session_id,
                source,
                cwd,
                description,
            } => {
                let mut task = Task::new(session_id.clone(), source, cwd);
                task.description = description;
                self.tasks.insert(session_id, task.clone());
                Some(task)
            }

            AgentEvent::ToolStart {
                session_id,
                tool_name,
                description,
            } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    task.update_tool(Some(tool_name), description);
                    task.update_status(TaskStatus::Running);
                    return Some(task.clone());
                }
                None
            }

            AgentEvent::ToolEnd {
                session_id,
                tool_name: _,
                success,
            } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    task.update_tool(None, None);
                    if !success {
                        task.update_status(TaskStatus::Error);
                    }
                    return Some(task.clone());
                }
                None
            }

            AgentEvent::WaitingForInput {
                session_id,
                message,
            } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    task.update_status(TaskStatus::WaitingForInput);
                    task.description = Some(message);
                    task.last_updated = Utc::now();
                    return Some(task.clone());
                }
                None
            }

            AgentEvent::SessionEnd { session_id, status } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    let final_status = status.unwrap_or(TaskStatus::Completed);
                    task.update_status(final_status);
                    return Some(task.clone());
                }
                None
            }

            AgentEvent::AgentTurnComplete {
                session_id,
                description,
            } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    task.description = description;
                    task.last_updated = Utc::now();
                    return Some(task.clone());
                }
                None
            }
        }
    }

    /// Cleanup completed tasks (older than 5 minutes)
    #[allow(dead_code)]
    pub fn cleanup_completed_tasks(&self) {
        let now = Utc::now();
        let timeout = chrono::Duration::minutes(5);

        self.tasks.retain(|_, task| match task.status {
            TaskStatus::Completed | TaskStatus::Error => {
                now.signed_duration_since(task.last_updated) < timeout
            }
            _ => true,
        });
    }

    /// Remove a task
    pub fn remove_task(&self, session_id: &str) -> Option<Task> {
        self.tasks.remove(session_id).map(|(_, task)| task)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::AgentSource;

    #[test]
    fn test_session_lifecycle() {
        let state = AppState::new();

        // Session start
        let event = AgentEvent::SessionStart {
            session_id: "test-123".to_string(),
            source: AgentSource::ClaudeCode,
            cwd: "/tmp/project".to_string(),
            description: Some("Initial description".to_string()),
        };
        let task = state.handle_event(event).unwrap();
        assert_eq!(task.status, TaskStatus::Running);
        assert_eq!(task.description, Some("Initial description".to_string()));

        // Tool start
        let event = AgentEvent::ToolStart {
            session_id: "test-123".to_string(),
            tool_name: "Write".to_string(),
            description: Some("Creating file".to_string()),
        };
        let task = state.handle_event(event).unwrap();
        assert_eq!(task.current_tool, Some("Write".to_string()));

        // Session end
        let event = AgentEvent::SessionEnd {
            session_id: "test-123".to_string(),
            status: None,
        };
        let task = state.handle_event(event).unwrap();
        assert_eq!(task.status, TaskStatus::Completed);
    }

    #[test]
    fn test_session_end_with_error() {
        let state = AppState::new();

        // Session start
        let event = AgentEvent::SessionStart {
            session_id: "test-456".to_string(),
            source: AgentSource::Codex,
            cwd: "/tmp/project".to_string(),
            description: None,
        };
        state.handle_event(event);

        // Session end with error
        let event = AgentEvent::SessionEnd {
            session_id: "test-456".to_string(),
            status: Some(TaskStatus::Error),
        };
        let task = state.handle_event(event).unwrap();
        assert_eq!(task.status, TaskStatus::Error);
    }
}
