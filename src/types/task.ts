// Agent source type
export type AgentSource = "claude_code" | "codex";

// Task status
export type TaskStatus =
  | "running"
  | "waiting_for_input"
  | "completed"
  | "error";

// Task data from backend
export interface Task {
  session_id: string;
  source: AgentSource;
  status: TaskStatus;
  current_tool?: string;
  description?: string;
  last_activity?: string;
  project_path: string;
  started_at: number; // Unix timestamp (seconds)
  last_updated: number; // Unix timestamp (seconds)
}

// Status display info
export interface StatusInfo {
  label: string;
  color: string;
  bgColor: string;
  icon: string;
}

// Status configuration
export const STATUS_CONFIG: Record<TaskStatus, StatusInfo> = {
  running: {
    label: "Running",
    color: "#2563eb",
    bgColor: "#dbeafe",
    icon: "\u25CF", // ●
  },
  waiting_for_input: {
    label: "Waiting",
    color: "#d97706",
    bgColor: "#fef3c7",
    icon: "\u25D0", // ◐
  },
  completed: {
    label: "Done",
    color: "#16a34a",
    bgColor: "#dcfce7",
    icon: "\u2713", // ✓
  },
  error: {
    label: "Error",
    color: "#dc2626",
    bgColor: "#fee2e2",
    icon: "\u2715", // ✕
  },
};

// Source display info
export const SOURCE_CONFIG: Record<
  AgentSource,
  { label: string; color: string; abbr: string }
> = {
  claude_code: {
    label: "Claude Code",
    color: "#D4A574",
    abbr: "CC",
  },
  codex: {
    label: "Codex",
    color: "#10A37F",
    abbr: "CX",
  },
};
