import { Task, STATUS_CONFIG } from "../types/task";
import { humanizeToolName } from "./format";

export function buildTaskSummary(task: Task, projectName?: string): string {
  const statusLabel = STATUS_CONFIG[task.status].label;
  const description = task.description?.trim() || task.last_activity?.trim();

  if (task.status === "waiting_for_input") {
    return description ? `${statusLabel}: ${description}` : `${statusLabel} for input`;
  }

  if (task.current_tool) {
    const toolLabel = humanizeToolName(task.current_tool);
    if (description) {
      return `${toolLabel}: ${description}`;
    }
    return `${statusLabel}: ${toolLabel}`;
  }

  if (description) {
    return `${statusLabel}: ${description}`;
  }

  if (projectName) {
    return `${statusLabel} · ${projectName}`;
  }

  return statusLabel;
}
