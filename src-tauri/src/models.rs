use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Agent source type
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum AgentSource {
    ClaudeCode,
    Codex,
}

impl std::fmt::Display for AgentSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AgentSource::ClaudeCode => write!(f, "Claude Code"),
            AgentSource::Codex => write!(f, "Codex"),
        }
    }
}

impl AgentSource {
    /// Returns the snake_case string representation for frontend
    pub fn as_snake_case(&self) -> &'static str {
        match self {
            AgentSource::ClaudeCode => "claude_code",
            AgentSource::Codex => "codex",
        }
    }
}

/// Task status
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Running,
    WaitingForInput,
    Completed,
    Error,
}

impl std::fmt::Display for TaskStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TaskStatus::Running => write!(f, "Running"),
            TaskStatus::WaitingForInput => write!(f, "Waiting for Input"),
            TaskStatus::Completed => write!(f, "Completed"),
            TaskStatus::Error => write!(f, "Error"),
        }
    }
}

impl TaskStatus {
    /// Returns the snake_case string representation for frontend
    pub fn as_snake_case(&self) -> &'static str {
        match self {
            TaskStatus::Running => "running",
            TaskStatus::WaitingForInput => "waiting_for_input",
            TaskStatus::Completed => "completed",
            TaskStatus::Error => "error",
        }
    }
}

/// Task information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub session_id: String,
    pub source: AgentSource,
    pub status: TaskStatus,
    pub current_tool: Option<String>,
    pub description: Option<String>,
    pub project_path: String,
    pub started_at: DateTime<Utc>,
    pub last_updated: DateTime<Utc>,
}

impl Task {
    pub fn new(session_id: String, source: AgentSource, project_path: String) -> Self {
        let now = Utc::now();
        Self {
            session_id,
            source,
            status: TaskStatus::Running,
            current_tool: None,
            description: None,
            project_path,
            started_at: now,
            last_updated: now,
        }
    }

    pub fn update_status(&mut self, status: TaskStatus) {
        self.status = status;
        self.last_updated = Utc::now();
    }

    pub fn update_tool(&mut self, tool: Option<String>, description: Option<String>) {
        self.current_tool = tool;
        self.description = description;
        self.last_updated = Utc::now();
    }
}

/// Events received from external agents (JSON-RPC params)
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum AgentEvent {
    SessionStart {
        session_id: String,
        source: AgentSource,
        cwd: String,
        description: Option<String>,
    },
    ToolStart {
        session_id: String,
        tool_name: String,
        description: Option<String>,
    },
    ToolEnd {
        session_id: String,
        #[allow(dead_code)]
        tool_name: String,
        success: bool,
    },
    WaitingForInput {
        session_id: String,
        message: String,
    },
    SessionEnd {
        session_id: String,
        status: Option<TaskStatus>,
    },
    AgentTurnComplete {
        session_id: String,
        description: Option<String>,
    },
}
