import { useState, useEffect, useCallback, useRef } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen, UnlistenFn } from '@tauri-apps/api/event';
import { Task } from '../types/task';
import { getUserMessage } from '../types/error';

const MAX_RETRIES = 3;
const RETRY_DELAY = 1000;

const waitForTauri = async (maxRetries = 10, delay = 100): Promise<boolean> => {
  for (let i = 0; i < maxRetries; i++) {
    if (typeof window !== 'undefined' && (window as any).__TAURI_INTERNALS__) {
      return true;
    }
    await new Promise(resolve => setTimeout(resolve, delay));
  }
  return false;
};

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
  const retryTimeoutId = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isMounted = useRef(true);
  const requestToken = useRef(0);

  // リトライタイマーをクリア
  const clearRetryTimeout = useCallback(() => {
    if (retryTimeoutId.current !== null) {
      clearTimeout(retryTimeoutId.current);
      retryTimeoutId.current = null;
    }
  }, []);

  const fetchTasks = useCallback(async (isRetry = false) => {
    // 新しいリクエスト開始時にトークンを更新
    const currentToken = isRetry ? requestToken.current : ++requestToken.current;

    try {
      if (!isRetry) {
        setIsLoading(true);
        setError(null);
        retryCount.current = 0;
        clearRetryTimeout(); // 新しいリクエスト時に既存のリトライをキャンセル
      }

      const result = await invoke<Task[]>('get_tasks');

      // アンマウント済み or 古いリクエストの場合は無視
      if (!isMounted.current || currentToken !== requestToken.current) {
        return;
      }

      setTasks(result);
      retryCount.current = 0;
      setIsLoading(false);
    } catch (err) {
      // アンマウント済み or 古いリクエストの場合は無視
      if (!isMounted.current || currentToken !== requestToken.current) {
        return;
      }

      const message = getUserMessage(err);

      if (retryCount.current < MAX_RETRIES) {
        retryCount.current++;
        console.warn(
          `Fetch failed, retrying (${retryCount.current}/${MAX_RETRIES})...`
        );
        retryTimeoutId.current = setTimeout(
          () => fetchTasks(true),
          RETRY_DELAY * retryCount.current
        );
        return;
      }

      setError(message);
      setIsLoading(false);
      console.error('Failed to fetch tasks:', err);
    }
  }, [clearRetryTimeout]);

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
    isMounted.current = true;
    let cancelled = false;
    let unlisten: UnlistenFn | null = null;

    const init = async () => {
      // Tauri ブリッジの準備を待つ
      const isReady = await waitForTauri();
      if (!isReady || cancelled || !isMounted.current) {
        if (!isReady && !cancelled && isMounted.current) {
          setIsLoading(false);
          setError('Tauri bridge is not available.');
        }
        return;
      }

      // Initial fetch
      fetchTasks();

      // Setup event listener for real-time updates
      const setupListener = async () => {
        try {
          const unlistenFn = await listen<Task[]>('tasks-updated', (event) => {
            if (isMounted.current) {
              setTasks(event.payload);
              setError(null);
            }
          });

          // listen() 完了時にアンマウント済みなら即座にクリーンアップ
          if (cancelled) {
            unlistenFn();
          } else {
            unlisten = unlistenFn;
          }
        } catch (err) {
          console.error('Failed to setup event listener:', err);
        }
      };

      setupListener();
    };

    init();

    // Cleanup on unmount
    return () => {
      cancelled = true;
      isMounted.current = false;
      clearRetryTimeout();
      if (unlisten) {
        unlisten();
      }
    };
  }, [fetchTasks, clearRetryTimeout]);

  return {
    tasks,
    isLoading,
    error,
    refresh: fetchTasks,
    dismissTask,
    clearError,
  };
}
