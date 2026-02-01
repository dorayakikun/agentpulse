import type { Task } from "../../types/task";
import {
  getInvokeConfig,
  getTasks,
  initMockBridge,
  setTasks,
} from "./mockState";

initMockBridge();

export const invoke = async <T>(command: string, payload?: unknown): Promise<T> => {
  const config = getInvokeConfig();
  if (config.delayMs > 0) {
    await new Promise((resolve) => setTimeout(resolve, config.delayMs));
  }
  switch (command) {
    case "get_tasks":
      if (config.getTasksError) {
        throw new Error(config.getTasksError);
      }
      return getTasks() as T;
    case "remove_task": {
      if (config.removeTaskError) {
        throw new Error(config.removeTaskError);
      }
      const data = payload as { sessionId?: string } | undefined;
      const sessionId = data?.sessionId;
      if (!sessionId) {
        throw new Error("Missing sessionId in payload");
      }
      const remaining = getTasks().filter((task) => task.session_id !== sessionId);
      setTasks(remaining as Task[]);
      return undefined as T;
    }
    default:
      throw new Error(`Mock invoke not implemented for command: ${command}`);
  }
};
