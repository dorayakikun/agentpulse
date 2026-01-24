# Phase 4: Frontend UI 実装計画

## 概要

Tauri 2.0 + React + TypeScript を使用して、AI Agent Status Monitor のフロントエンド UI を実装します。メニューバーアプリのポップオーバーとして表示され、Claude Code / Codex のタスク状況をリアルタイムで表示します。

---

## 1. ディレクトリ構造

```
src/
├── main.tsx                    # エントリポイント
├── App.tsx                     # メインコンポーネント
├── App.css                     # グローバルスタイル
├── components/
│   ├── TaskList.tsx            # タスク一覧コンポーネント
│   ├── TaskItem.tsx            # 個別タスク表示
│   ├── StatusBadge.tsx         # ステータスバッジ
│   ├── SourceIcon.tsx          # Claude Code / Codex アイコン
│   ├── EmptyState.tsx          # 空状態表示
│   └── Header.tsx              # ヘッダー（タイトル・アクション）
├── hooks/
│   └── useTasks.ts             # タスク状態管理カスタムフック
├── types/
│   └── task.ts                 # TypeScript 型定義
├── utils/
│   └── format.ts               # ユーティリティ関数
└── styles/
    └── variables.css           # CSS 変数（色・サイズ）
```

---

## 2. 型定義

### src/types/task.ts

```typescript
// タスクのソース種別
export type AgentSource = 'claude_code' | 'codex';

// タスクのステータス
export type TaskStatus = 'running' | 'waiting_for_input' | 'completed' | 'error';

// Backend から受け取るタスクデータ
export interface Task {
  session_id: string;
  source: AgentSource;
  status: TaskStatus;
  current_tool?: string;
  description?: string;
  project_path: string;
  started_at: number;       // Unix timestamp (秒)
  last_updated: number;     // Unix timestamp (秒)
}

// Tauri イベントペイロード
export interface TasksUpdatedPayload {
  tasks: Task[];
}

// ステータス表示情報
export interface StatusInfo {
  label: string;
  color: string;
  bgColor: string;
  icon: string;
}
```

---

## 3. コンポーネント設計

### 3.1 App.tsx

```typescript
import { useTasks } from './hooks/useTasks';
import { Header } from './components/Header';
import { TaskList } from './components/TaskList';
import { EmptyState } from './components/EmptyState';

function App() {
  const { tasks, isLoading, error, refresh } = useTasks();

  return (
    <div className="app">
      <Header taskCount={tasks.length} onRefresh={refresh} />
      <main className="main">
        {isLoading ? (
          <div className="loading">Loading...</div>
        ) : error ? (
          <div className="error">{error}</div>
        ) : tasks.length === 0 ? (
          <EmptyState />
        ) : (
          <TaskList tasks={tasks} />
        )}
      </main>
    </div>
  );
}
```

**責務:**
- アプリ全体のレイアウト管理
- ローディング / エラー / 空状態 / タスク一覧の条件分岐

### 3.2 TaskList.tsx

```typescript
import { Task } from '../types/task';
import { TaskItem } from './TaskItem';

interface TaskListProps {
  tasks: Task[];
}

export const TaskList: FC<TaskListProps> = ({ tasks }) => {
  // ステータス優先度でソート: running > waiting_for_input > completed > error
  const sortedTasks = [...tasks].sort((a, b) => {
    const priority = { running: 0, waiting_for_input: 1, completed: 2, error: 3 };
    return priority[a.status] - priority[b.status];
  });

  return (
    <ul className="task-list">
      {sortedTasks.map((task) => (
        <TaskItem key={task.session_id} task={task} />
      ))}
    </ul>
  );
};
```

### 3.3 TaskItem.tsx

```typescript
import { Task } from '../types/task';
import { StatusBadge } from './StatusBadge';
import { SourceIcon } from './SourceIcon';

interface TaskItemProps {
  task: Task;
}

export const TaskItem: FC<TaskItemProps> = ({ task }) => {
  return (
    <li className={`task-item task-item--${task.source}`}>
      <div className="task-item-header">
        <SourceIcon source={task.source} />
        <span className="project-name">{getProjectName(task.project_path)}</span>
        <StatusBadge status={task.status} />
      </div>

      <div className="task-item-body">
        {task.current_tool && (
          <div className="current-tool">
            <span className="tool-label">Tool:</span>
            <code className="tool-name">{task.current_tool}</code>
          </div>
        )}
        {task.description && (
          <p className="task-description">{task.description}</p>
        )}
      </div>

      <div className="task-item-footer">
        <span className="time-ago">{formatRelativeTime(task.last_updated)}</span>
      </div>
    </li>
  );
};
```

### 3.4 StatusBadge.tsx

```typescript
import { TaskStatus } from '../types/task';

const STATUS_CONFIG = {
  running: { label: 'Running', color: '#2563eb', bgColor: '#dbeafe', icon: '●' },
  waiting_for_input: { label: 'Waiting', color: '#d97706', bgColor: '#fef3c7', icon: '◐' },
  completed: { label: 'Done', color: '#16a34a', bgColor: '#dcfce7', icon: '✓' },
  error: { label: 'Error', color: '#dc2626', bgColor: '#fee2e2', icon: '✕' },
};

export const StatusBadge: FC<{ status: TaskStatus }> = ({ status }) => {
  const config = STATUS_CONFIG[status];
  return (
    <span className={`status-badge status-badge--${status}`}
          style={{ color: config.color, backgroundColor: config.bgColor }}>
      <span className={`status-icon ${status === 'running' ? 'pulse' : ''}`}>
        {config.icon}
      </span>
      {config.label}
    </span>
  );
};
```

### 3.5 SourceIcon.tsx

```typescript
import { AgentSource } from '../types/task';

export const SourceIcon: FC<{ source: AgentSource }> = ({ source }) => {
  if (source === 'claude_code') {
    return (
      <span className="source-icon" title="Claude Code">
        <svg width="16" height="16" viewBox="0 0 24 24">
          <circle cx="12" cy="12" r="10" fill="#D4A574" />
          <text x="12" y="16" textAnchor="middle" fill="white" fontSize="12">C</text>
        </svg>
      </span>
    );
  }
  return (
    <span className="source-icon" title="Codex">
      <svg width="16" height="16" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="10" fill="#10A37F" />
        <text x="12" y="16" textAnchor="middle" fill="white" fontSize="12">X</text>
      </svg>
    </span>
  );
};
```

**視覚的区別:**

| ソース | 色 | アイコン |
|--------|-----|---------|
| Claude Code | #D4A574 (Anthropic オレンジ) | C |
| Codex | #10A37F (OpenAI グリーン) | X |

---

## 4. 状態管理

### src/hooks/useTasks.ts

```typescript
import { useState, useEffect, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen, UnlistenFn } from '@tauri-apps/api/event';
import { Task, TasksUpdatedPayload } from '../types/task';

export function useTasks() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchTasks = useCallback(async () => {
    try {
      setIsLoading(true);
      const result = await invoke<Task[]>('get_tasks');
      setTasks(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch tasks');
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchTasks();

    let unlisten: UnlistenFn | null = null;
    const setupListener = async () => {
      unlisten = await listen<TasksUpdatedPayload>('tasks-updated', (event) => {
        setTasks(event.payload.tasks);
      });
    };
    setupListener();

    return () => { unlisten?.(); };
  }, [fetchTasks]);

  return { tasks, isLoading, error, refresh: fetchTasks };
}
```

**機能:**
1. 初回ロード時に `invoke('get_tasks')` で全タスク取得
2. `listen('tasks-updated')` でリアルタイム更新を購読
3. アンマウント時にリスナー解除

---

## 5. UI/UX 設計

### 5.1 ポップオーバーレイアウト

```
┌─────────────────────────────────────┐
│  AI Agent Status          2 tasks  │  ← Header (32px)
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │ [C] my-project      [Running ●] │ │  ← TaskItem
│ │ Tool: Read file                  │ │
│ │ 2 min ago                        │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ [X] another-proj    [Waiting ◐] │ │
│ │ Awaiting user input              │ │
│ │ 5 min ago                        │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**サイズ指定:**
- 幅: 320px (固定)
- 最大高さ: 400px
- タスクアイテム高さ: 約 72px

### 5.2 ステータス表示

| ステータス | 色 | アイコン | アニメーション |
|-----------|-----|---------|---------------|
| Running | 青 (#2563eb) | ● | パルス |
| Waiting | 黄 (#d97706) | ◐ | なし |
| Done | 緑 (#16a34a) | ✓ | なし |
| Error | 赤 (#dc2626) | ✕ | なし |

---

## 6. スタイリング

### 6.1 CSS 変数 (src/styles/variables.css)

```css
:root {
  /* Colors */
  --color-bg-primary: rgba(255, 255, 255, 0.92);
  --color-text-primary: #1d1d1f;
  --color-text-secondary: #6e6e73;
  --color-border: rgba(0, 0, 0, 0.1);

  /* Status Colors */
  --color-running: #2563eb;
  --color-waiting: #d97706;
  --color-completed: #16a34a;
  --color-error: #dc2626;

  /* Source Colors */
  --color-claude: #D4A574;
  --color-codex: #10A37F;

  /* Spacing */
  --spacing-sm: 8px;
  --spacing-md: 12px;
  --spacing-lg: 16px;

  /* Font */
  --font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', sans-serif;
}

/* Dark Mode */
@media (prefers-color-scheme: dark) {
  :root {
    --color-bg-primary: rgba(30, 30, 30, 0.92);
    --color-text-primary: #f5f5f7;
    --color-text-secondary: #a1a1a6;
    --color-border: rgba(255, 255, 255, 0.1);
  }
}
```

### 6.2 macOS ネイティブデザイン指針

- **背景**: 半透明のビブランシー効果
- **角丸**: 8px
- **フォント**: SF Pro（システムフォント）
- **シャドウ**: 軽いドロップシャドウ

---

## 7. ユーティリティ

### src/utils/format.ts

```typescript
export function getProjectName(projectPath: string): string {
  const parts = projectPath.split('/');
  return parts[parts.length - 1] || projectPath;
}

export function formatRelativeTime(timestamp: number): string {
  const diff = Math.floor(Date.now() / 1000) - timestamp;
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)} min ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} hour(s) ago`;
  return `${Math.floor(diff / 86400)} day(s) ago`;
}
```

---

## 8. 実装順序

### 依存関係を考慮した順序

| Step | ファイル | 依存 |
|------|----------|------|
| 1 | `src/types/task.ts` | なし |
| 2 | `src/styles/variables.css` | なし |
| 3 | `src/utils/format.ts` | types |
| 4 | `src/hooks/useTasks.ts` | types |
| 5 | `src/components/StatusBadge.tsx` | types |
| 6 | `src/components/SourceIcon.tsx` | types |
| 7 | `src/components/EmptyState.tsx` | なし |
| 8 | `src/components/TaskItem.tsx` | StatusBadge, SourceIcon, utils |
| 9 | `src/components/TaskList.tsx` | TaskItem |
| 10 | `src/components/Header.tsx` | なし |
| 11 | `src/App.css` | variables.css |
| 12 | `src/App.tsx` | 全コンポーネント, useTasks |
| 13 | `src/main.tsx` | App |

---

## 9. テスト項目

### 手動テスト

1. **初期表示**: アプリ起動時に空状態が表示される
2. **タスク表示**: タスクがある場合、一覧が正しく表示される
3. **リアルタイム更新**: Backend からイベント受信で UI が更新される
4. **ステータス表示**: 各ステータスが正しい色とアイコンで表示
5. **ソース区別**: Claude Code と Codex が視覚的に区別できる
6. **スクロール**: タスクが多い場合、スクロールが機能する
7. **ダークモード**: システム設定に応じて切り替わる

### 開発用モックデータ

```typescript
const MOCK_TASKS: Task[] = [
  {
    session_id: 'cc-123',
    source: 'claude_code',
    status: 'running',
    current_tool: 'Read',
    description: 'Reading configuration files',
    project_path: '/Users/dev/my-project',
    started_at: Date.now() / 1000 - 120,
    last_updated: Date.now() / 1000 - 30,
  },
  {
    session_id: 'codex-456',
    source: 'codex',
    status: 'waiting_for_input',
    description: 'Awaiting user confirmation',
    project_path: '/Users/dev/another-project',
    started_at: Date.now() / 1000 - 300,
    last_updated: Date.now() / 1000 - 60,
  },
];
```

---

## Critical Files

1. **`src/types/task.ts`** - 全コンポーネントが依存する型定義
2. **`src/hooks/useTasks.ts`** - Tauri API 連携の状態管理フック
3. **`src/components/TaskItem.tsx`** - タスク表示の中核コンポーネント
4. **`src/App.css`** - macOS ネイティブデザインのスタイル定義
5. **`src/App.tsx`** - 全コンポーネントを統合するメインコンポーネント
