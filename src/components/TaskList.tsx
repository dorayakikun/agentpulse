import { Task, TaskStatus } from "../types/task";
import { TaskItem } from "./TaskItem";
import "./TaskList.css";

interface TaskListProps {
  tasks: Task[];
  onDismiss?: (sessionId: string) => void;
}

// Status priority for sorting
const STATUS_PRIORITY: Record<TaskStatus, number> = {
  running: 0,
  waiting_for_input: 1,
  completed: 2,
  error: 3,
};

export function TaskList({ tasks, onDismiss }: TaskListProps) {
  // Sort by status priority, then by last_updated (most recent first)
  const sortedTasks = [...tasks].sort((a, b) => {
    const priorityDiff = STATUS_PRIORITY[a.status] - STATUS_PRIORITY[b.status];
    if (priorityDiff !== 0) return priorityDiff;
    return b.last_updated - a.last_updated;
  });

  return (
    <ul className="task-list">
      {sortedTasks.map((task) => (
        <TaskItem key={task.session_id} task={task} onDismiss={onDismiss} />
      ))}
    </ul>
  );
}
