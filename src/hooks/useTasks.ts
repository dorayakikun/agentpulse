import { useState, useEffect, useCallback, useRef } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen, UnlistenFn } from '@tauri-apps/api/event';
import { Task } from '../types/task';
import { getUserMessage } from '../types/error';

const MAX_RETRIES = 3;
const RETRY_DELAY = 1000;

interface UseTasksReturn {
  tasks: Task[];
  isLoading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  dismissTask: (sessionId: string) => Promise<void>;
  clearError: () => void;
}

export function useTasks(): UseTasksReturn {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const retryCount = useRef(0);

  const fetchTasks = useCallback(async (isRetry = false) => {
    try {
      if (!isRetry) {
        setIsLoading(true);
        setError(null);
        retryCount.current = 0; // 新しい手動リフレッシュ時にリセット
      }

      const result = await invoke<Task[]>('get_tasks');
      setTasks(result);
      retryCount.current = 0; // 成功時にリセット
      setIsLoading(false); // 成功時のみローディング解除
    } catch (err) {
      const message = getUserMessage(err);

      if (retryCount.current < MAX_RETRIES) {
        retryCount.current++;
        console.warn(
          `Fetch failed, retrying (${retryCount.current}/${MAX_RETRIES})...`
        );
        setTimeout(() => fetchTasks(true), RETRY_DELAY * retryCount.current);
        // リトライ中はローディング状態を維持
        return;
      }

      // リトライ上限に達した場合のみエラーを設定してローディング解除
      setError(message);
      setIsLoading(false);
      console.error('Failed to fetch tasks:', err);
    }
  }, []);

  const dismissTask = useCallback(async (sessionId: string) => {
    try {
      await invoke('remove_task', { sessionId });
      setTasks((prev) => prev.filter((t) => t.session_id !== sessionId));
    } catch (err) {
      console.error('Failed to dismiss task:', err);
    }
  }, []);

  const clearError = useCallback(() => setError(null), []);

  useEffect(() => {
    // Initial fetch
    fetchTasks();

    // Setup event listener for real-time updates
    let unlisten: UnlistenFn | null = null;

    const setupListener = async () => {
      try {
        unlisten = await listen<Task[]>('tasks-updated', (event) => {
          setTasks(event.payload);
          setError(null); // エラークリア
        });
      } catch (err) {
        console.error('Failed to setup event listener:', err);
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
    clearError,
  };
}
