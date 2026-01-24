import { TaskStatus, STATUS_CONFIG } from "../types/task";
import "./StatusBadge.css";

interface StatusBadgeProps {
  status: TaskStatus;
}

export function StatusBadge({ status }: StatusBadgeProps) {
  const config = STATUS_CONFIG[status];

  return (
    <span
      className={`status-badge status-badge--${status}`}
      style={{
        color: config.color,
        backgroundColor: config.bgColor,
      }}
    >
      <span className={`status-icon ${status === "running" ? "pulse" : ""}`}>
        {config.icon}
      </span>
      {config.label}
    </span>
  );
}
