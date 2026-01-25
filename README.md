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

- macOS 12.0 以上 / Linux
- [Rust](https://www.rust-lang.org/tools/install)
- [Node.js](https://nodejs.org/) 18 以上
- jq (`brew install jq` / `apt install jq`)

## 開発

```bash
# 依存関係のインストール
npm install

# 開発サーバー起動
npm run tauri dev

# ビルド
npm run tauri build
```

## CLI ツール連携

AI Agent Status Monitor は Claude Code と Codex からイベントを受信し、
タスクの進捗状況をリアルタイムで表示します。

### 前提条件

```bash
# jq のインストール (macOS)
brew install jq

# jq のインストール (Ubuntu/Debian)
sudo apt-get install jq
```

### Claude Code の設定

```bash
# 自動インストール（推奨）
./scripts/install-claude-hooks.sh
```

手動で設定する場合、`~/.claude/settings.json` に以下を追加:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "/path/to/scripts/claude-code-hook.sh session_start" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "/path/to/scripts/claude-code-hook.sh pre_tool" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "/path/to/scripts/claude-code-hook.sh post_tool" }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          { "type": "command", "command": "/path/to/scripts/claude-code-hook.sh notification" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "/path/to/scripts/claude-code-hook.sh session_end" }
        ]
      }
    ]
  }
}
```

### Codex の設定

```bash
# 自動インストール（推奨）
./scripts/install-codex-notify.sh
```

手動で設定する場合、`~/.codex/config.toml` に以下を追加:

```toml
notify = ["bash", "/path/to/scripts/codex-notify.sh"]
```

### 動作確認

1. AI Agent Status Monitor を起動
2. メニューバーにアイコンが表示されることを確認
3. テストスクリプトを実行:
   ```bash
   ./scripts/test-hooks.sh
   ```
4. タスク一覧にテストセッションが表示されることを確認
5. Claude Code または Codex でセッションを開始
6. タスク一覧にセッションが表示されることを確認

## トラブルシューティング

| 問題 | 原因 | 解決方法 |
|------|------|----------|
| タスクが表示されない | ソケット未接続 | アプリを起動し、`ls -la /tmp/ai-agent-status.sock` で確認 |
| jq: command not found | jq 未インストール | `brew install jq` (macOS) |
| Permission denied | スクリプト実行権限なし | `chmod +x scripts/*.sh` |
| 設定が反映されない | Claude Code 再起動が必要 | Claude Code を再起動 |

### デバッグ方法

```bash
# ソケット接続確認
echo '{"jsonrpc":"2.0","method":"ping","id":1}' | nc -U /tmp/ai-agent-status.sock

# 手動でイベント送信
echo '{"session_id":"debug-test","cwd":"/tmp"}' | ./scripts/claude-code-hook.sh session_start

# ログファイル確認 (macOS)
tail -f ~/Library/Logs/AI\ Agent\ Status/ai-agent-status*.log
```

## 技術スタック

- **Frontend**: React 18 + TypeScript + Vite
- **Backend**: Rust + Tauri 2.0
- **通信**: Unix Domain Socket + JSON-RPC
- **ロギング**: tracing + tracing-subscriber

## ライセンス

MIT
