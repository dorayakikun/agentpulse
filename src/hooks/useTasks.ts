import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen, UnlistenFn } from "@tauri-apps/api/event";
import { Task } from "../types/task";

interface UseTasksReturn {
  tasks: Task[];
  isLoading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  dismissTask: (sessionId: string) => Promise<void>;
}

export function useTasks(): UseTasksReturn {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchTasks = useCallback(async () => {
    try {
      setIsLoading(true);
      setError(null);
      const result = await invoke<Task[]>("get_tasks");
      setTasks(result);
    } catch (err) {
      console.error("Failed to fetch tasks:", err);
      setError(err instanceof Error ? err.message : "Failed to fetch tasks");
    } finally {
      setIsLoading(false);
    }
  }, []);

  const dismissTask = useCallback(async (sessionId: string) => {
    try {
      await invoke("remove_task", { sessionId });
      setTasks((prev) => prev.filter((t) => t.session_id !== sessionId));
    } catch (err) {
      console.error("Failed to dismiss task:", err);
    }
  }, []);

  useEffect(() => {
    // Initial fetch
    fetchTasks();

    // Setup event listener for real-time updates
    let unlisten: UnlistenFn | null = null;

    const setupListener = async () => {
      try {
        unlisten = await listen<Task[]>("tasks-updated", (event) => {
          setTasks(event.payload);
        });
      } catch (err) {
        console.error("Failed to setup event listener:", err);
      }
    };

    setupListener();

    // Cleanup on unmount
    return () => {
      if (unlisten) {
        unlisten();
      }
    };
  }, [fetchTasks]);

  return {
    tasks,
    isLoading,
    error,
    refresh: fetchTasks,
    dismissTask,
  };
}
