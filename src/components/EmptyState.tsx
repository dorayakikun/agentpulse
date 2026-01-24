import "./EmptyState.css";

export function EmptyState() {
  return (
    <div className="empty-state">
      <div className="empty-icon">
        <svg
          width="48"
          height="48"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
        >
          <rect x="3" y="3" width="18" height="18" rx="2" />
          <line x1="9" y1="9" x2="15" y2="9" />
          <line x1="9" y1="13" x2="15" y2="13" />
          <line x1="9" y1="17" x2="12" y2="17" />
        </svg>
      </div>
      <p className="empty-title">No active tasks</p>
      <p className="empty-hint">
        Tasks will appear when Claude Code or Codex starts running
      </p>
    </div>
  );
}
