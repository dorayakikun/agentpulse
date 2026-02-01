#!/bin/bash
# scripts/codex-notify.sh
# Script invoked from Codex notify configuration
# Usage: codex-notify.sh '<json>'

set -euo pipefail

DEBUG_LOG="/tmp/codex-notify-debug.log"
DEBUG="${CODEX_NOTIFY_DEBUG:-0}"

log_debug() {
    if [[ "$DEBUG" == "1" ]]; then
        echo "$1" >> "$DEBUG_LOG"
    fi
}

# Log at start (for debugging) - record before early exits
log_debug "[codex-notify] Script called at $(date)"
log_debug "[codex-notify] Arg1: ${1:-empty}"

SOCKET="/tmp/agentpulse.sock"
INPUT="${1:-}"

# If arg is empty and stdin is available, read from stdin
if [[ -z "$INPUT" && ! -t 0 ]]; then
    INPUT="$(cat -)"
fi

# Exit if socket does not exist (app not running)
if [[ ! -S "$SOCKET" ]]; then
    log_debug "[codex-notify] Socket not found, exiting"
    exit 0
fi

# Exit if there is no input
if [[ -z "$INPUT" ]]; then
    log_debug "[codex-notify] No input, exiting"
    exit 0
fi

# Additional debug info
log_debug "[codex-notify] INPUT: $INPUT"
log_debug "[codex-notify] SOCKET exists: yes"
log_debug "[codex-notify] PID: $$"

# Send JSON-RPC message
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

# Field extraction helper
get_field() {
    echo "$INPUT" | jq -r "$1 // empty"
}

# Get Codex event type
EVENT_TYPE=$(get_field '.type // .event')
THREAD_ID=$(get_field '."thread-id" // .thread_id // .session_id')
CWD=$(get_field '.cwd // ."project-path" // .project_path')

# If user input flag exists, reflect it in the event type
NEEDS_USER_INPUT=$(get_field '.waiting_for_input // .awaiting_user_input // .requires_user_input // .needs_user_input // .user_input_required')
if [[ "$NEEDS_USER_INPUT" == "true" ]]; then
    EVENT_TYPE="waiting-for-input"
fi

log_debug "[codex-notify] EVENT_TYPE: $EVENT_TYPE"
log_debug "[codex-notify] THREAD_ID(raw): $THREAD_ID"
log_debug "[codex-notify] CWD: $CWD"

# Hash generation (macOS/Linux compatible)
generate_hash() {
    local input="$1"
    if command -v md5sum &>/dev/null; then
        echo "$input" | md5sum | cut -d' ' -f1 | head -c 16
    elif command -v md5 &>/dev/null; then
        # macOS md5 command
        echo "$input" | md5 | head -c 16
    elif command -v shasum &>/dev/null; then
        echo "$input" | shasum -a 256 | cut -d' ' -f1 | head -c 16
    else
        # Fallback: generate random string
        echo "$$-$RANDOM-$(date +%s)" | head -c 16
    fi
}

# Generate session ID if thread_id is missing
if [[ -z "$THREAD_ID" ]]; then
    if [[ -n "$CWD" ]]; then
        # If cwd exists, hash cwd
        THREAD_ID=$(generate_hash "$CWD")
    else
        # If cwd is empty, generate unique ID (timestamp + PID + random)
        THREAD_ID=$(generate_hash "${EPOCHSECONDS:-$(date +%s)}-$$-$RANDOM")
    fi
fi

# Send session start (safe if already exists)
ensure_session_start() {
    if [[ -n "$THREAD_ID" && -n "$CWD" ]]; then
        local params
        params=$(jq -nc \
            --arg session_id "$THREAD_ID" \
            --arg project_path "$CWD" \
            '{
                session_id: $session_id,
                source: "codex",
                project_path: $project_path
            }')
        send_message "task.start" "$params"
    fi
}

case "$EVENT_TYPE" in
    agent-turn-start)
        # Agent turn start
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
        # Command execution start / patch apply start
        COMMAND=$(get_field '.command')

        ensure_session_start

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
        # Command execution end / patch apply end
        EXIT_CODE=$(get_field '.exit_code')

        ensure_session_start

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

    approval-requested|waiting-for-input|input-required|user-input-required|user-input-requested|prompt-user|user-prompt|assistant-question|input-requested)
        # Approval request / waiting for user input
        MESSAGE=$(get_field '.message // .prompt // .question // .content // .text // .reason')

        ensure_session_start

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
        # Agent turn complete
        LAST_MESSAGE=$(get_field '."last-assistant-message" // .last_assistant_message')

        # Codex notify only emits completion events, so start may be missing
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
        # Error occurred
        ERROR_MESSAGE=$(get_field '.error')

        ensure_session_start

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
        # Log unknown events (debug)
        log_debug "[codex-notify] Unknown event type: $EVENT_TYPE"
        log_debug "[codex-notify] Full input: $INPUT"
        ;;
esac

exit 0
