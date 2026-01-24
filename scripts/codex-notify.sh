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
