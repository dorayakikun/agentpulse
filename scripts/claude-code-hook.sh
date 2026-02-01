#!/bin/bash
# scripts/claude-code-hook.sh
# Claude Code Hooks から呼び出されるスクリプト
# Usage: claude-code-hook.sh <event_type>
#   event_type: session_start | pre_tool | post_tool | notification | session_end

set -euo pipefail

SOCKET="/tmp/agentpulse.sock"
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
    message=$(jq -nc \
        --arg method "$method" \
        --argjson params "$params" \
        '{jsonrpc: "2.0", method: $method, params: $params, id: null}')

    printf '%s\n' "$message" | nc -U "$SOCKET" -w 1 2>/dev/null || true
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
            PARAMS=$(jq -nc \
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
            PARAMS=$(jq -nc \
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

            PARAMS=$(jq -nc \
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
                permission_prompt|idle_prompt|user_prompt|input_required|input-required|waiting_for_input)
                    PARAMS=$(jq -nc \
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

            PARAMS=$(jq -nc \
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
