import { Task } from "../types/task";
import { StatusBadge } from "./StatusBadge";
import { SourceIcon } from "./SourceIcon";
import { getProjectName, formatRelativeTime, truncate } from "../utils/format";
import { buildTaskSummary } from "../utils/taskSummary";
import "./TaskItem.css";

interface TaskItemProps {
  task: Task;
  onDismiss?: (sessionId: string) => void;
}

export function TaskItem({ task, onDismiss }: TaskItemProps) {
  const projectName = getProjectName(task.project_path);
  const canDismiss = task.status === "completed" || task.status === "error";
  const summary = buildTaskSummary(task, projectName);

  return (
    <li className={`task-item task-item--${task.source}`}>
      <div className="task-item-header">
        <SourceIcon source={task.source} />
        <span className="project-name" title={task.project_path}>
          {truncate(projectName, 24)}
        </span>
        <StatusBadge status={task.status} />
      </div>

      <div className="task-item-body">
        {summary && (
          <p className="task-summary" title={summary}>
            {truncate(summary, 80)}
          </p>
        )}
        {task.current_tool && (
          <div className="current-tool">
            <span className="tool-label">Tool:</span>
            <code className="tool-name">{task.current_tool}</code>
          </div>
        )}
        {task.description && (
          <p className="task-description" title={task.description}>
            {truncate(task.description, 60)}
          </p>
        )}
      </div>

      <div className="task-item-footer">
        <span className="time-ago">{formatRelativeTime(task.last_updated)}</span>
        {canDismiss && onDismiss && (
          <button
            className="dismiss-btn"
            onClick={() => onDismiss(task.session_id)}
          >
            Dismiss
          </button>
        )}
      </div>
    </li>
  );
}
