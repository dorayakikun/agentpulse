#!/bin/bash
# scripts/codex-notify.sh
# Codex の notify 設定から呼び出されるスクリプト
# Usage: codex-notify.sh '<json>'

set -euo pipefail

DEBUG_LOG="/tmp/codex-notify-debug.log"
DEBUG="${CODEX_NOTIFY_DEBUG:-0}"

log_debug() {
    if [[ "$DEBUG" == "1" ]]; then
        echo "$1" >> "$DEBUG_LOG"
    fi
}

# 最初にログ出力（デバッグ用）- 早期終了前に記録
log_debug "[codex-notify] Script called at $(date)"
log_debug "[codex-notify] Arg1: ${1:-empty}"

SOCKET="/tmp/ai-agent-status.sock"
INPUT="${1:-}"

# 引数が空で stdin がある場合は stdin から読み込む
if [[ -z "$INPUT" && ! -t 0 ]]; then
    INPUT="$(cat -)"
fi

# ソケットが存在しない場合は終了（アプリ未起動）
if [[ ! -S "$SOCKET" ]]; then
    log_debug "[codex-notify] Socket not found, exiting"
    exit 0
fi

# 入力がない場合は終了
if [[ -z "$INPUT" ]]; then
    log_debug "[codex-notify] No input, exiting"
    exit 0
fi

# 追加のデバッグ情報
log_debug "[codex-notify] INPUT: $INPUT"
log_debug "[codex-notify] SOCKET exists: yes"
log_debug "[codex-notify] PID: $$"

# JSON-RPC メッセージを送信する関数
send_message() {
    local method="$1"
    local params="$2"
    local message
    message=$(jq -nc \
        --arg method "$method" \
        --argjson params "$params" \
        '{jsonrpc: "2.0", method: $method, params: $params, id: null}')

    log_debug "[codex-notify] SEND method=$method params=$params"
    echo "$message" | nc -U "$SOCKET" -w 1 >/dev/null 2>&1 || true
}

# フィールド抽出ヘルパー
get_field() {
    echo "$INPUT" | jq -r "$1 // empty"
}

# Codex イベントタイプを取得
EVENT_TYPE=$(get_field '.type // .event')
THREAD_ID=$(get_field '."thread-id" // .thread_id // .session_id')
CWD=$(get_field '.cwd // ."project-path" // .project_path')

log_debug "[codex-notify] EVENT_TYPE: $EVENT_TYPE"
log_debug "[codex-notify] THREAD_ID(raw): $THREAD_ID"
log_debug "[codex-notify] CWD: $CWD"

# ハッシュ生成関数（macOS/Linux両対応）
generate_hash() {
    local input="$1"
    if command -v md5sum &>/dev/null; then
        echo "$input" | md5sum | cut -d' ' -f1 | head -c 16
    elif command -v md5 &>/dev/null; then
        # macOS の md5 コマンド
        echo "$input" | md5 | head -c 16
    elif command -v shasum &>/dev/null; then
        echo "$input" | shasum -a 256 | cut -d' ' -f1 | head -c 16
    else
        # フォールバック: ランダムな文字列を生成
        echo "$$-$RANDOM-$(date +%s)" | head -c 16
    fi
}

# thread_id がない場合はセッション ID を生成
if [[ -z "$THREAD_ID" ]]; then
    if [[ -n "$CWD" ]]; then
        # cwd がある場合は cwd からハッシュ生成
        THREAD_ID=$(generate_hash "$CWD")
    else
        # cwd も空の場合はユニークな ID を生成（タイムスタンプ + PID + ランダム）
        THREAD_ID=$(generate_hash "${EPOCHSECONDS:-$(date +%s)}-$$-$RANDOM")
    fi
fi

case "$EVENT_TYPE" in
    agent-turn-start)
        # エージェントターン開始
        PARAMS=$(jq -nc \
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

        PARAMS=$(jq -nc \
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

        PARAMS=$(jq -nc \
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

        PARAMS=$(jq -nc \
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
        LAST_MESSAGE=$(get_field '."last-assistant-message" // .last_assistant_message')

        # Codex notify は完了イベントのみのため、開始が未送信の可能性がある
        START_PARAMS=$(jq -nc \
            --arg session_id "$THREAD_ID" \
            --arg project_path "$CWD" \
            '{
                session_id: $session_id,
                source: "codex",
                project_path: $project_path
            }')
        send_message "task.start" "$START_PARAMS"

        PARAMS=$(jq -nc \
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

        PARAMS=$(jq -nc \
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
        # 不明なイベントをログに記録（デバッグ用）
        log_debug "[codex-notify] Unknown event type: $EVENT_TYPE"
        log_debug "[codex-notify] Full input: $INPUT"
        ;;
esac

exit 0
