# AI Agent Status Monitor - 要件定義

## 概要
Claude Code / Codex を複数動かした時にタスクの進捗状況を一覧管理するメニューバーアプリ

## 詳細計画ファイル
- **Phase 1**: `./phase1-foundation.md` - 基盤構築の詳細計画
- **Phase 2**: `./phase2-ipc-server.md` - IPC サーバー実装の詳細計画
- **Phase 3**: `./phase3-notification.md` - 通知機能の詳細計画
- **Phase 4**: `./phase4-frontend.md` - Frontend UI 実装の詳細計画

## 確定要件

| 項目 | 内容 |
|------|------|
| 言語/FW | Rust + Tauri 2.0 |
| UI形式 | macOS メニューバーアプリ |
| 対応OS | macOS (優先)、将来的に Linux/Windows |
| 履歴保存 | 不要（実行中タスクのみ） |
| 通知 | OS ネイティブ通知 |
| CC連携 | Hooks 機能 |
| Codex連携 | notify 設定 |

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│         AI Agent Status Monitor                 │
│         (Tauri メニューバーアプリ)               │
├─────────────────────────────────────────────────┤
│  Frontend (React)  ◄─IPC─►  Backend (Rust)      │
│  - タスク一覧 UI            - 状態管理          │
│                             - Socket Server     │
│                             - 通知処理          │
└───────────────────────┬─────────────────────────┘
                        │
              Unix Domain Socket
              (/tmp/ai-agent-status.sock)
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   Claude Code     Claude Code       Codex
    (Hooks)         (Hooks)        (notify)
```

## ディレクトリ構造

```
ai-agent-status/
├── src-tauri/
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   └── src/
│       ├── main.rs           # エントリポイント
│       ├── lib.rs            # メインライブラリ
│       ├── models.rs         # データモデル
│       ├── state.rs          # 状態管理
│       ├── socket_server.rs  # UDS サーバー
│       ├── notification.rs   # 通知処理
│       ├── tray.rs           # メニューバー
│       └── commands.rs       # Tauri コマンド
├── src/
│   ├── main.tsx
│   ├── App.tsx               # メイン UI
│   ├── components/
│   │   ├── TaskList.tsx
│   │   ├── TaskItem.tsx
│   │   └── StatusBadge.tsx
│   └── hooks/
│       └── useTasks.ts
├── scripts/
│   ├── claude-code-hook.sh   # CC 用フック (Bash)
│   └── codex-notify.sh       # Codex 用通知 (Bash)
├── package.json
└── README.md
```

## 主要データモデル

```rust
pub enum AgentSource { ClaudeCode, Codex }

pub enum TaskStatus {
    Running,           // 実行中
    WaitingForInput,   // 入力待ち
    Completed,         // 完了
    Error,             // エラー
}

pub struct Task {
    session_id: String,
    source: AgentSource,
    status: TaskStatus,
    current_tool: Option<String>,
    description: Option<String>,
    project_path: String,
    started_at: SystemTime,
    last_updated: SystemTime,
}
```

## 開発ステップ

### Phase 1: 基盤構築
1. `npm create tauri-app@latest` でプロジェクト作成
2. メニューバーアプリ設定 (`tauri.conf.json`)
3. 状態管理実装 (`state.rs`)

### Phase 2: IPC サーバー実装
1. Unix Domain Socket サーバー (`socket_server.rs`)
2. JSON-RPC プロトコルでイベント受信
3. Frontend への Tauri events 発行

### Phase 3: 通知機能実装
1. `tauri-plugin-notification` で macOS 通知
2. タスク完了時・入力待ち時に通知

### Phase 4: Frontend UI 実装
1. React でタスク一覧 UI
2. Claude Code / Codex の視覚的区別（アイコン・色）
3. リアルタイム更新

### Phase 5: CLI ツール連携
1. Claude Code Hooks スクリプト作成
2. Codex notify スクリプト作成
3. ユーザー向けセットアップガイド

### Phase 6: 品質向上
1. エラーハンドリング
2. ロギング
3. macOS 署名・公証

## CLI ツール連携設定

### Claude Code (~/.claude/settings.json)
```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "claude-code-hook.sh session_start" }] }],
    "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "claude-code-hook.sh pre_tool" }] }],
    "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "claude-code-hook.sh post_tool" }] }],
    "Notification": [{ "matcher": "permission_prompt|idle_prompt", "hooks": [{ "type": "command", "command": "claude-code-hook.sh notification" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "claude-code-hook.sh session_end" }] }]
  }
}
```

### Codex (~/.codex/config.toml)
```toml
notify = ["bash", "/path/to/codex-notify.sh"]
```

## 通知スクリプト詳細

両スクリプトは **Bash + jq + nc** で統一。依存: `jq`, `nc` (netcat)

### claude-code-hook.sh
- **入力**: stdin から JSON
- **処理**: `jq` でパースし、イベント種別に応じたメッセージを構築
- **出力**: `nc -U /tmp/ai-agent-status.sock` でソケット送信

```bash
#!/bin/bash
SOCKET="/tmp/ai-agent-status.sock"
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
# ... イベント種別に応じて JSON-RPC メッセージを構築
echo "$MESSAGE" | nc -U "$SOCKET"
```

### codex-notify.sh
- **入力**: コマンドライン引数 `$1` に JSON
- **処理**: `jq` でパースし、イベント種別に応じたメッセージを構築
- **出力**: `nc -U /tmp/ai-agent-status.sock` でソケット送信

```bash
#!/bin/bash
SOCKET="/tmp/ai-agent-status.sock"
INPUT="$1"
EVENT_TYPE=$(echo "$INPUT" | jq -r '.type // empty')
# ... イベント種別に応じて JSON-RPC メッセージを構築
echo "$MESSAGE" | nc -U "$SOCKET"
```

### 依存パッケージのインストール (macOS)
```bash
brew install jq  # nc は macOS 標準搭載
```

## 主要クレート

| クレート | 用途 |
|----------|------|
| tauri (2.x) | フレームワーク |
| tokio | 非同期ランタイム |
| serde/serde_json | シリアライズ |
| tauri-plugin-notification | OS 通知 |
| dashmap | スレッドセーフ Map |
| uuid | セッション ID |

## 検証方法

1. **基本動作**: アプリ起動 → メニューバーにアイコン表示 → クリックでウィンドウ表示
2. **Claude Code 連携**: Hooks 設定 → `claude` コマンド実行 → タスク一覧に表示
3. **Codex 連携**: notify 設定 → `codex` コマンド実行 → タスク一覧に表示
4. **通知**: タスク完了時・入力待ち時に macOS 通知が表示
5. **識別**: Claude Code / Codex のタスクが視覚的に区別できる
