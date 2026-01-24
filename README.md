# AgentPulse

Claude Code / Codex などの AI エージェントの進捗状況を一覧管理する macOS メニューバーアプリ

## 特徴

- メニューバーからワンクリックで全エージェントの状態を確認
- Claude Code / Codex の視覚的な区別（アイコン・色分け）
- タスク完了・入力待ち時の OS ネイティブ通知
- 軽量・常駐型アプリ

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│              AgentPulse                         │
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

## 必要条件

- macOS 12.0 以上
- [Rust](https://www.rust-lang.org/tools/install)
- [Node.js](https://nodejs.org/) 18 以上
- jq (`brew install jq`)

## 開発

```bash
# 依存関係のインストール
npm install

# 開発サーバー起動
npm run tauri dev

# ビルド
npm run tauri build
```

## セットアップ

### Claude Code

`~/.claude/settings.json` に以下を追加:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "/path/to/scripts/claude-code-hook.sh session_start" }] }],
    "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/path/to/scripts/claude-code-hook.sh pre_tool" }] }],
    "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/path/to/scripts/claude-code-hook.sh post_tool" }] }],
    "Notification": [{ "matcher": "permission_prompt|idle_prompt", "hooks": [{ "type": "command", "command": "/path/to/scripts/claude-code-hook.sh notification" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "/path/to/scripts/claude-code-hook.sh session_end" }] }]
  }
}
```

### Codex

`~/.codex/config.toml` に以下を追加:

```toml
notify = ["bash", "/path/to/scripts/codex-notify.sh"]
```

## 技術スタック

- **Frontend**: React 18 + TypeScript + Vite
- **Backend**: Rust + Tauri 2.0
- **通信**: Unix Domain Socket + JSON-RPC

## ライセンス

MIT
