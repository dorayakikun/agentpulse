# Phase 5: CLI ツール連携 - 詳細設計

## 概要

Claude Code と Codex から AI Agent Status Monitor にイベントを送信するための連携スクリプトと、ユーザー向けセットアップガイドの実装計画。

---

## 1. 前提条件

### 1.1 依存パッケージ

```bash
# macOS (Homebrew)
brew install jq  # JSON パーサー
# nc (netcat) は macOS 標準搭載

# Linux (Debian/Ubuntu)
sudo apt-get install jq netcat-openbsd

# Linux (RHEL/Fedora)
sudo dnf install jq nmap-ncat
```

### 1.2 ソケットパス

```
/tmp/ai-agent-status.sock
```

---

## 2. Claude Code Hooks スクリプト

### 2.1 ファイル構成

```
scripts/
├── claude-code-hook.sh      # メインフックスクリプト
└── install-claude-hooks.sh  # 設定インストーラー
```

### 2.2 claude-code-hook.sh

```bash
#!/bin/bash
# scripts/claude-code-hook.sh
# Claude Code Hooks から呼び出されるスクリプト
# Usage: claude-code-hook.sh <event_type>
#   event_type: session_start | pre_tool | post_tool | notification | session_end

set -euo pipefail

SOCKET="/tmp/ai-agent-status.sock"
EVENT_TYPE="${1:-}"

# ソケットが存在しない場合は終了（アプリ未起動）
if [[ ! -S "$SOCKET" ]]; then
    exit 0
fi

# stdin から JSON を読み取り
INPUT=$(cat)

# デバッグ用（開発時のみ有効化）
# echo "[DEBUG] Event: $EVENT_TYPE" >&2
# echo "[DEBUG] Input: $INPUT" >&2

# JSON-RPC メッセージを送信する関数
send_message() {
    local method="$1"
    local params="$2"
    local message
    message=$(jq -n \
        --arg method "$method" \
        --argjson params "$params" \
        '{jsonrpc: "2.0", method: $method, params: $params, id: null}')

    echo "$message" | nc -U "$SOCKET" -w 1 2>/dev/null || true
}

# フィールド抽出ヘルパー
get_field() {
    echo "$INPUT" | jq -r "$1 // empty"
}

# イベント種別に応じた処理
case "$EVENT_TYPE" in
    session_start)
        # セッション開始
        SESSION_ID=$(get_field '.session_id')
        CWD=$(get_field '.cwd')

        if [[ -n "$SESSION_ID" && -n "$CWD" ]]; then
            PARAMS=$(jq -n \
                --arg session_id "$SESSION_ID" \
                --arg project_path "$CWD" \
                '{
                    session_id: $session_id,
                    source: "claude_code",
                    project_path: $project_path
                }')
            send_message "task.start" "$PARAMS"
        fi
        ;;

    pre_tool)
        # ツール実行前
        SESSION_ID=$(get_field '.session_id')
        TOOL_NAME=$(get_field '.tool_name')
        TOOL_INPUT=$(get_field '.tool_input | tostring' 2>/dev/null || echo "")

        # tool_input から description を抽出（可能であれば）
        DESCRIPTION=""
        if [[ -n "$TOOL_INPUT" ]]; then
            DESCRIPTION=$(echo "$TOOL_INPUT" | jq -r '.description // .file_path // .command // empty' 2>/dev/null || echo "")
        fi

        if [[ -n "$SESSION_ID" && -n "$TOOL_NAME" ]]; then
            PARAMS=$(jq -n \
                --arg session_id "$SESSION_ID" \
                --arg status "running" \
                --arg current_tool "$TOOL_NAME" \
                --arg description "$DESCRIPTION" \
                '{
                    session_id: $session_id,
                    status: $status,
                    current_tool: $current_tool,
                    description: (if $description == "" then null else $description end)
                }')
            send_message "task.update" "$PARAMS"
        fi
        ;;

    post_tool)
        # ツール実行後
        SESSION_ID=$(get_field '.session_id')
        TOOL_NAME=$(get_field '.tool_name')
        TOOL_ERROR=$(get_field '.tool_error')

        if [[ -n "$SESSION_ID" ]]; then
            if [[ -n "$TOOL_ERROR" && "$TOOL_ERROR" != "null" ]]; then
                STATUS="error"
                DESCRIPTION="$TOOL_NAME failed: $TOOL_ERROR"
            else
                STATUS="running"
                DESCRIPTION=""
            fi

            PARAMS=$(jq -n \
                --arg session_id "$SESSION_ID" \
                --arg status "$STATUS" \
                --arg description "$DESCRIPTION" \
                '{
                    session_id: $session_id,
                    status: $status,
                    current_tool: null,
                    description: (if $description == "" then null else $description end)
                }')
            send_message "task.update" "$PARAMS"
        fi
        ;;

    notification)
        # 通知イベント（permission_prompt, idle_prompt）
        SESSION_ID=$(get_field '.session_id')
        NOTIFICATION_TYPE=$(get_field '.type')
        MESSAGE=$(get_field '.message')

        if [[ -n "$SESSION_ID" ]]; then
            case "$NOTIFICATION_TYPE" in
                permission_prompt|idle_prompt)
                    PARAMS=$(jq -n \
                        --arg session_id "$SESSION_ID" \
                        --arg status "waiting_for_input" \
                        --arg description "$MESSAGE" \
                        '{
                            session_id: $session_id,
                            status: $status,
                            description: (if $description == "" then null else $description end)
                        }')
                    send_message "task.update" "$PARAMS"
                    ;;
            esac
        fi
        ;;

    session_end)
        # セッション終了
        SESSION_ID=$(get_field '.session_id')
        EXIT_REASON=$(get_field '.reason')

        if [[ -n "$SESSION_ID" ]]; then
            case "$EXIT_REASON" in
                exit|timeout|error)
                    STATUS="completed"
                    ;;
                *)
                    STATUS="completed"
                    ;;
            esac

            PARAMS=$(jq -n \
                --arg session_id "$SESSION_ID" \
                --arg status "$STATUS" \
                '{
                    session_id: $session_id,
                    status: $status
                }')
            send_message "task.end" "$PARAMS"
        fi
        ;;

    *)
        # 不明なイベントは無視
        ;;
esac

exit 0
```

### 2.3 install-claude-hooks.sh

```bash
#!/bin/bash
# scripts/install-claude-hooks.sh
# Claude Code の settings.json に Hooks 設定を追加するスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/claude-code-hook.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

# スクリプトに実行権限を付与
chmod +x "$HOOK_SCRIPT"

# 設定ディレクトリがなければ作成
mkdir -p "$(dirname "$SETTINGS_FILE")"

# 新しい hooks 設定
HOOKS_CONFIG=$(cat <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT session_start" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT pre_tool" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT post_tool" }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT notification" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT session_end" }
        ]
      }
    ]
  }
}
EOF
)

# 既存の settings.json がある場合はマージ
if [[ -f "$SETTINGS_FILE" ]]; then
    echo "Existing settings found at $SETTINGS_FILE"
    echo "Merging hooks configuration..."

    # 既存の設定と新しい hooks をマージ
    MERGED=$(jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$HOOKS_CONFIG"))

    # バックアップを作成
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup.$(date +%Y%m%d%H%M%S)"

    echo "$MERGED" > "$SETTINGS_FILE"
else
    echo "Creating new settings file at $SETTINGS_FILE"
    echo "$HOOKS_CONFIG" > "$SETTINGS_FILE"
fi

echo ""
echo "Claude Code Hooks configuration installed successfully!"
echo ""
echo "Hook script location: $HOOK_SCRIPT"
echo "Settings file: $SETTINGS_FILE"
echo ""
echo "To verify, run: cat $SETTINGS_FILE | jq '.hooks'"
```

---

## 3. Codex notify スクリプト

### 3.1 ファイル構成

```
scripts/
├── codex-notify.sh          # メイン通知スクリプト
└── install-codex-notify.sh  # 設定インストーラー
```

### 3.2 codex-notify.sh

```bash
#!/bin/bash
# scripts/codex-notify.sh
# Codex の notify 設定から呼び出されるスクリプト
# Usage: codex-notify.sh '<json>'

set -euo pipefail

SOCKET="/tmp/ai-agent-status.sock"
INPUT="${1:-}"

# ソケットが存在しない場合は終了（アプリ未起動）
if [[ ! -S "$SOCKET" ]]; then
    exit 0
fi

# 入力がない場合は終了
if [[ -z "$INPUT" ]]; then
    exit 0
fi

# デバッグ用（開発時のみ有効化）
# echo "[DEBUG] Input: $INPUT" >&2

# JSON-RPC メッセージを送信する関数
send_message() {
    local method="$1"
    local params="$2"
    local message
    message=$(jq -n \
        --arg method "$method" \
        --argjson params "$params" \
        '{jsonrpc: "2.0", method: $method, params: $params, id: null}')

    echo "$message" | nc -U "$SOCKET" -w 1 2>/dev/null || true
}

# フィールド抽出ヘルパー
get_field() {
    echo "$INPUT" | jq -r "$1 // empty"
}

# Codex イベントタイプを取得
EVENT_TYPE=$(get_field '.type')
THREAD_ID=$(get_field '.thread_id')
CWD=$(get_field '.cwd')

# thread_id がない場合は cwd からセッション ID を生成
if [[ -z "$THREAD_ID" ]]; then
    THREAD_ID=$(echo "$CWD" | md5sum | cut -d' ' -f1 | head -c 16)
fi

case "$EVENT_TYPE" in
    agent-turn-start)
        # エージェントターン開始
        PARAMS=$(jq -n \
            --arg session_id "$THREAD_ID" \
            --arg project_path "$CWD" \
            '{
                session_id: $session_id,
                source: "codex",
                project_path: $project_path
            }')
        send_message "task.start" "$PARAMS"
        ;;

    exec-command-start|apply-patch-start)
        # コマンド実行開始 / パッチ適用開始
        COMMAND=$(get_field '.command')

        PARAMS=$(jq -n \
            --arg session_id "$THREAD_ID" \
            --arg status "running" \
            --arg current_tool "$EVENT_TYPE" \
            --arg description "$COMMAND" \
            '{
                session_id: $session_id,
                status: $status,
                current_tool: $current_tool,
                description: (if $description == "" then null else $description end)
            }')
        send_message "task.update" "$PARAMS"
        ;;

    exec-command-end|apply-patch-end)
        # コマンド実行終了 / パッチ適用終了
        EXIT_CODE=$(get_field '.exit_code')

        if [[ "$EXIT_CODE" != "0" && -n "$EXIT_CODE" ]]; then
            STATUS="error"
        else
            STATUS="running"
        fi

        PARAMS=$(jq -n \
            --arg session_id "$THREAD_ID" \
            --arg status "$STATUS" \
            '{
                session_id: $session_id,
                status: $status,
                current_tool: null
            }')
        send_message "task.update" "$PARAMS"
        ;;

    approval-requested)
        # 承認要求
        MESSAGE=$(get_field '.message')

        PARAMS=$(jq -n \
            --arg session_id "$THREAD_ID" \
            --arg status "waiting_for_input" \
            --arg description "$MESSAGE" \
            '{
                session_id: $session_id,
                status: $status,
                description: (if $description == "" then "Codex is waiting for approval" else $description end)
            }')
        send_message "task.update" "$PARAMS"
        ;;

    agent-turn-complete)
        # エージェントターン完了
        LAST_MESSAGE=$(get_field '.last_assistant_message')

        PARAMS=$(jq -n \
            --arg session_id "$THREAD_ID" \
            --arg status "completed" \
            --arg description "$LAST_MESSAGE" \
            '{
                session_id: $session_id,
                status: $status,
                description: (if $description == "" then null else $description end)
            }')
        send_message "task.end" "$PARAMS"
        ;;

    error)
        # エラー発生
        ERROR_MESSAGE=$(get_field '.error')

        PARAMS=$(jq -n \
            --arg session_id "$THREAD_ID" \
            --arg status "error" \
            --arg description "$ERROR_MESSAGE" \
            '{
                session_id: $session_id,
                status: $status,
                description: (if $description == "" then "An error occurred" else $description end)
            }')
        send_message "task.end" "$PARAMS"
        ;;

    *)
        # 不明なイベントは無視
        ;;
esac

exit 0
```

### 3.3 install-codex-notify.sh

```bash
#!/bin/bash
# scripts/install-codex-notify.sh
# Codex の config.toml に notify 設定を追加するスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/codex-notify.sh"
CONFIG_FILE="$HOME/.codex/config.toml"

# スクリプトに実行権限を付与
chmod +x "$NOTIFY_SCRIPT"

# 設定ディレクトリがなければ作成
mkdir -p "$(dirname "$CONFIG_FILE")"

# notify 設定行
NOTIFY_LINE="notify = [\"bash\", \"$NOTIFY_SCRIPT\"]"

# 既存の config.toml がある場合
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Existing config found at $CONFIG_FILE"

    # バックアップを作成
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"

    # notify 設定が既に存在するか確認
    if grep -q "^notify\s*=" "$CONFIG_FILE"; then
        echo "Updating existing notify configuration..."
        # 既存の notify 行を置換
        sed -i.bak "s|^notify\s*=.*|$NOTIFY_LINE|" "$CONFIG_FILE"
        rm -f "${CONFIG_FILE}.bak"
    else
        echo "Adding notify configuration..."
        echo "" >> "$CONFIG_FILE"
        echo "$NOTIFY_LINE" >> "$CONFIG_FILE"
    fi
else
    echo "Creating new config file at $CONFIG_FILE"
    echo "$NOTIFY_LINE" > "$CONFIG_FILE"
fi

echo ""
echo "Codex notify configuration installed successfully!"
echo ""
echo "Notify script location: $NOTIFY_SCRIPT"
echo "Config file: $CONFIG_FILE"
echo ""
echo "To verify, run: cat $CONFIG_FILE"
```

---

## 4. Claude Code Hooks 入力データ仕様

### 4.1 SessionStart

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "cwd": "/Users/dev/my-project"
}
```

### 4.2 PreToolUse

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "tool_name": "Read",
  "tool_input": {
    "file_path": "/Users/dev/my-project/src/main.rs"
  }
}
```

### 4.3 PostToolUse

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "tool_name": "Read",
  "tool_output": "...",
  "tool_error": null
}
```

### 4.4 Notification

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "permission_prompt",
  "message": "Do you want to allow this action?"
}
```

### 4.5 SessionEnd

```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "reason": "exit"
}
```

---

## 5. Codex notify 入力データ仕様

### 5.1 agent-turn-start

```json
{
  "type": "agent-turn-start",
  "thread_id": "thread_abc123",
  "cwd": "/Users/dev/my-project"
}
```

### 5.2 exec-command-start

```json
{
  "type": "exec-command-start",
  "thread_id": "thread_abc123",
  "cwd": "/Users/dev/my-project",
  "command": "npm test"
}
```

### 5.3 approval-requested

```json
{
  "type": "approval-requested",
  "thread_id": "thread_abc123",
  "cwd": "/Users/dev/my-project",
  "message": "Allow running: npm install lodash?"
}
```

### 5.4 agent-turn-complete

```json
{
  "type": "agent-turn-complete",
  "thread_id": "thread_abc123",
  "cwd": "/Users/dev/my-project",
  "last_assistant_message": "I have completed the task."
}
```

---

## 6. ユーザー向けセットアップガイド

### 6.1 README.md への追記内容

```markdown
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
# 自動インストール
./scripts/install-claude-hooks.sh

# または手動設定
# ~/.claude/settings.json を編集して hooks を追加
```

手動で設定する場合、以下を `~/.claude/settings.json` に追加:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "/path/to/claude-code-hook.sh session_start" }] }
    ],
    "PreToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "/path/to/claude-code-hook.sh pre_tool" }] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "/path/to/claude-code-hook.sh post_tool" }] }
    ],
    "Notification": [
      { "matcher": "permission_prompt|idle_prompt", "hooks": [{ "type": "command", "command": "/path/to/claude-code-hook.sh notification" }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "/path/to/claude-code-hook.sh session_end" }] }
    ]
  }
}
```

### Codex の設定

```bash
# 自動インストール
./scripts/install-codex-notify.sh

# または手動設定
# ~/.codex/config.toml を編集
```

手動で設定する場合、以下を `~/.codex/config.toml` に追加:

```toml
notify = ["bash", "/path/to/codex-notify.sh"]
```

### 動作確認

1. AI Agent Status Monitor を起動
2. メニューバーにアイコンが表示されることを確認
3. Claude Code または Codex でセッションを開始
4. タスク一覧にセッションが表示されることを確認
```

---

## 7. テスト

### 7.1 ユニットテスト用スクリプト

```bash
#!/bin/bash
# scripts/test-hooks.sh
# フックスクリプトのテスト

SOCKET="/tmp/ai-agent-status.sock"

echo "=== Testing claude-code-hook.sh ==="

# session_start テスト
echo '{"session_id":"test-123","cwd":"/tmp/test-project"}' | \
    ./claude-code-hook.sh session_start
echo "Sent session_start"

# pre_tool テスト
echo '{"session_id":"test-123","tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}' | \
    ./claude-code-hook.sh pre_tool
echo "Sent pre_tool"

# post_tool テスト
echo '{"session_id":"test-123","tool_name":"Read","tool_output":"file contents"}' | \
    ./claude-code-hook.sh post_tool
echo "Sent post_tool"

# notification テスト
echo '{"session_id":"test-123","type":"permission_prompt","message":"Allow this?"}' | \
    ./claude-code-hook.sh notification
echo "Sent notification"

# session_end テスト
echo '{"session_id":"test-123","reason":"exit"}' | \
    ./claude-code-hook.sh session_end
echo "Sent session_end"

echo ""
echo "=== Testing codex-notify.sh ==="

# agent-turn-start テスト
./codex-notify.sh '{"type":"agent-turn-start","thread_id":"codex-456","cwd":"/tmp/codex-project"}'
echo "Sent agent-turn-start"

# exec-command-start テスト
./codex-notify.sh '{"type":"exec-command-start","thread_id":"codex-456","cwd":"/tmp/codex-project","command":"npm test"}'
echo "Sent exec-command-start"

# approval-requested テスト
./codex-notify.sh '{"type":"approval-requested","thread_id":"codex-456","cwd":"/tmp/codex-project","message":"Allow npm install?"}'
echo "Sent approval-requested"

# agent-turn-complete テスト
./codex-notify.sh '{"type":"agent-turn-complete","thread_id":"codex-456","cwd":"/tmp/codex-project","last_assistant_message":"Done!"}'
echo "Sent agent-turn-complete"

echo ""
echo "=== Tests completed ==="
```

### 7.2 統合テスト手順

| Step | 操作 | 期待結果 |
|------|------|----------|
| 1 | AI Agent Status Monitor を起動 | メニューバーにアイコン表示 |
| 2 | `./scripts/test-hooks.sh` を実行 | エラーなく完了 |
| 3 | メニューバーアイコンをクリック | テストタスクが一覧に表示 |
| 4 | Claude Code で実際のセッション開始 | 新しいタスクが表示 |
| 5 | ツール実行 | ステータスが更新 |
| 6 | セッション終了 | タスクが完了状態に |
| 7 | Codex でセッション開始 | 別のタスクが表示 |

### 7.3 エラーケーステスト

| ケース | 入力 | 期待動作 |
|--------|------|----------|
| ソケット未存在 | 任意のイベント | エラーなく終了 (exit 0) |
| 空の入力 | 空文字列 | エラーなく終了 |
| 不正な JSON | `{invalid}` | エラーなく終了 |
| 未知のイベント | `unknown_event` | 無視して終了 |

---

## 8. 実装順序

### チェックリスト

```
□ 1. scripts/ ディレクトリ作成

□ 2. claude-code-hook.sh (新規)
  □ send_message 関数
  □ session_start ハンドラ
  □ pre_tool ハンドラ
  □ post_tool ハンドラ
  □ notification ハンドラ
  □ session_end ハンドラ

□ 3. install-claude-hooks.sh (新規)
  □ 既存設定のマージ
  □ バックアップ作成
  □ 設定ファイル更新

□ 4. codex-notify.sh (新規)
  □ send_message 関数
  □ agent-turn-start ハンドラ
  □ exec-command-start ハンドラ
  □ approval-requested ハンドラ
  □ agent-turn-complete ハンドラ
  □ error ハンドラ

□ 5. install-codex-notify.sh (新規)
  □ 既存設定の更新
  □ バックアップ作成

□ 6. test-hooks.sh (新規)
  □ Claude Code テスト
  □ Codex テスト

□ 7. README.md 更新
  □ セットアップ手順
  □ 動作確認方法
  □ トラブルシューティング
```

---

## 9. トラブルシューティングガイド

### 9.1 よくある問題と解決方法

| 問題 | 原因 | 解決方法 |
|------|------|----------|
| タスクが表示されない | ソケット未接続 | アプリを起動し、`ls -la /tmp/ai-agent-status.sock` で確認 |
| jq: command not found | jq 未インストール | `brew install jq` (macOS) |
| Permission denied | スクリプト実行権限なし | `chmod +x scripts/*.sh` |
| 設定が反映されない | Claude Code 再起動が必要 | Claude Code を再起動 |

### 9.2 デバッグ方法

```bash
# ソケット接続確認
echo '{"jsonrpc":"2.0","method":"ping","id":1}' | nc -U /tmp/ai-agent-status.sock

# スクリプトのデバッグ出力を有効化
# claude-code-hook.sh / codex-notify.sh 内のデバッグ行をアンコメント

# 手動でイベント送信
echo '{"session_id":"debug-test","cwd":"/tmp"}' | ./scripts/claude-code-hook.sh session_start
```

---

## 10. セキュリティ考慮事項

### 10.1 ソケットパーミッション

- ソケットファイルは `0600` (owner only) で作成
- 他のユーザーからのアクセスを防止

### 10.2 入力検証

- すべての入力は `jq` でパースし、不正な JSON は無視
- シェルインジェクション対策として変数はダブルクォート

### 10.3 エラーハンドリング

- ソケット未接続時はサイレントに終了
- Claude Code / Codex の動作を阻害しない

---

## Critical Files

| ファイル | 役割 |
|----------|------|
| `scripts/claude-code-hook.sh` | Claude Code イベントをソケットに送信 |
| `scripts/codex-notify.sh` | Codex イベントをソケットに送信 |
| `scripts/install-claude-hooks.sh` | Claude Code 設定インストーラー |
| `scripts/install-codex-notify.sh` | Codex 設定インストーラー |
| `scripts/test-hooks.sh` | 統合テスト用スクリプト |
| `README.md` | ユーザー向けセットアップガイド |
