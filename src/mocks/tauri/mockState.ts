import type { Task } from "../../types/task";

type EventHandler<T = unknown> = (event: { payload: T }) => void;

const listeners = new Map<string, Set<EventHandler>>();
let tasks: Task[] = [];
let invokeConfig: {
  delayMs: number;
  getTasksError?: string;
  removeTaskError?: string;
} = { delayMs: 0 };

const emit = (eventName: string, payload: unknown) => {
  const handlers = listeners.get(eventName);
  if (!handlers) {
    return;
  }
  handlers.forEach((handler) => handler({ payload }));
};

const addListener = <T>(eventName: string, handler: EventHandler<T>) => {
  if (!listeners.has(eventName)) {
    listeners.set(eventName, new Set());
  }
  const handlers = listeners.get(eventName)!;
  handlers.add(handler as EventHandler);

  return () => {
    handlers.delete(handler as EventHandler);
  };
};

const getTasks = () => tasks;

const setTasks = (next: Task[]) => {
  tasks = next;
  emit("tasks-updated", tasks);
};

const getInvokeConfig = () => invokeConfig;

const setInvokeConfig = (next: Partial<typeof invokeConfig>) => {
  invokeConfig = { ...invokeConfig, ...next };
};

const clearInvokeConfig = () => {
  invokeConfig = { delayMs: 0 };
};

const reset = () => {
  tasks = [];
  invokeConfig = { delayMs: 0 };
};

const initMockBridge = () => {
  if (typeof window === "undefined") {
    return;
  }

  const globalAny = window as any;
  if (!globalAny.__TAURI_INTERNALS__) {
    globalAny.__TAURI_INTERNALS__ = {};
  }
  if (!globalAny.__TAURI_MOCK__) {
    globalAny.__TAURI_MOCK__ = {
      getTasks,
      getInvokeConfig,
      setInvokeConfig,
      clearInvokeConfig,
      setTasks,
      emit,
      reset,
    };
  }

  if (globalAny.__TAURI_E2E_CONFIG__) {
    setInvokeConfig(globalAny.__TAURI_E2E_CONFIG__);
  }
};

export {
  addListener,
  emit,
  getInvokeConfig,
  getTasks,
  clearInvokeConfig,
  initMockBridge,
  reset,
  setInvokeConfig,
  setTasks,
};
