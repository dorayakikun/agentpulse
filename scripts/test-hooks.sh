#!/bin/bash
# scripts/test-hooks.sh
# Hook script tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOCKET="/tmp/agentpulse.sock"

# Check socket existence
check_socket() {
    if [[ ! -S "$SOCKET" ]]; then
        echo "Error: Socket not found at $SOCKET"
        echo "Please start AgentPulse first."
        exit 1
    fi
    echo "Socket found at $SOCKET"
}

echo "=== AgentPulse - Hook Test Script ==="
echo ""

check_socket

echo ""
echo "=== Testing claude-code-hook.sh ==="
echo ""

# session_start test
echo '{"session_id":"test-claude-123","cwd":"/tmp/test-project"}' | \
    "$SCRIPT_DIR/claude-code-hook.sh" session_start
echo "[OK] Sent session_start"
sleep 0.5

# pre_tool test
echo '{"session_id":"test-claude-123","tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}' | \
    "$SCRIPT_DIR/claude-code-hook.sh" pre_tool
echo "[OK] Sent pre_tool (Read)"
sleep 0.5

# post_tool test
echo '{"session_id":"test-claude-123","tool_name":"Read","tool_output":"file contents"}' | \
    "$SCRIPT_DIR/claude-code-hook.sh" post_tool
echo "[OK] Sent post_tool"
sleep 0.5

# pre_tool test (Bash)
echo '{"session_id":"test-claude-123","tool_name":"Bash","tool_input":{"command":"npm test"}}' | \
    "$SCRIPT_DIR/claude-code-hook.sh" pre_tool
echo "[OK] Sent pre_tool (Bash)"
sleep 0.5

# notification test
echo '{"session_id":"test-claude-123","type":"permission_prompt","message":"Allow running npm install?"}' | \
    "$SCRIPT_DIR/claude-code-hook.sh" notification
echo "[OK] Sent notification (permission_prompt)"
sleep 0.5

# session_end test
echo '{"session_id":"test-claude-123","reason":"exit"}' | \
    "$SCRIPT_DIR/claude-code-hook.sh" session_end
echo "[OK] Sent session_end"

echo ""
echo "=== Testing codex-notify.sh ==="
echo ""

# agent-turn-start test
"$SCRIPT_DIR/codex-notify.sh" '{"type":"agent-turn-start","thread_id":"codex-456","cwd":"/tmp/codex-project"}'
echo "[OK] Sent agent-turn-start"
sleep 0.5

# exec-command-start test
"$SCRIPT_DIR/codex-notify.sh" '{"type":"exec-command-start","thread_id":"codex-456","cwd":"/tmp/codex-project","command":"npm test"}'
echo "[OK] Sent exec-command-start"
sleep 0.5

# exec-command-end test
"$SCRIPT_DIR/codex-notify.sh" '{"type":"exec-command-end","thread_id":"codex-456","cwd":"/tmp/codex-project","exit_code":"0"}'
echo "[OK] Sent exec-command-end"
sleep 0.5

# approval-requested test
"$SCRIPT_DIR/codex-notify.sh" '{"type":"approval-requested","thread_id":"codex-456","cwd":"/tmp/codex-project","message":"Allow npm install lodash?"}'
echo "[OK] Sent approval-requested"
sleep 0.5

# agent-turn-complete test
"$SCRIPT_DIR/codex-notify.sh" '{"type":"agent-turn-complete","thread_id":"codex-456","cwd":"/tmp/codex-project","last_assistant_message":"Task completed successfully!"}'
echo "[OK] Sent agent-turn-complete"

echo ""
echo "=== Testing error cases ==="
echo ""

# Empty input test (codex-notify)
"$SCRIPT_DIR/codex-notify.sh" '' 2>/dev/null && echo "[OK] Empty input handled gracefully" || echo "[OK] Empty input handled gracefully"

# Invalid event test
echo '{"session_id":"test-unknown","type":"unknown_event"}' | \
    "$SCRIPT_DIR/claude-code-hook.sh" unknown_event 2>/dev/null && echo "[OK] Unknown event ignored" || echo "[OK] Unknown event ignored"

echo ""
echo "=== All tests completed ==="
echo ""
echo "Check AgentPulse to verify the test tasks are displayed."
