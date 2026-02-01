#!/bin/bash
# Test script for AgentPulse socket server

SOCKET="/tmp/agentpulse.sock"
SESSION_ID="test-session-$(date +%s)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

send_request() {
    local method="$1"
    local params="$2"
    echo -e "${YELLOW}>>> Request: ${method}${NC}"
    local request="{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}"
    echo "    $request"
    local response=$(echo "$request" | nc -U "$SOCKET")
    echo -e "${GREEN}<<< Response:${NC}"
    echo "    $response"
    echo ""
}

# Check if socket exists
if [ ! -S "$SOCKET" ]; then
    echo -e "${RED}Error: Socket file not found at $SOCKET${NC}"
    echo "Make sure the AgentPulse app is running."
    exit 1
fi

echo "================================"
echo "AgentPulse Socket Test"
echo "Session ID: $SESSION_ID"
echo "================================"
echo ""

# Test ping
echo "=== Test 1: Ping ==="
send_request "ping" "null"

# Test task.start
echo "=== Test 2: Task Start ==="
send_request "task.start" "{\"session_id\":\"${SESSION_ID}\",\"source\":\"claude_code\",\"project_path\":\"/tmp/test-project\",\"description\":\"Testing socket communication\"}"

# Test task.update (running with tool)
echo "=== Test 3: Task Update (Tool Start) ==="
send_request "task.update" "{\"session_id\":\"${SESSION_ID}\",\"status\":\"running\",\"current_tool\":\"Write\",\"description\":\"Writing test file\"}"

# Test task.update (waiting for input)
echo "=== Test 4: Task Update (Waiting) ==="
send_request "task.update" "{\"session_id\":\"${SESSION_ID}\",\"status\":\"waiting_for_input\",\"description\":\"Waiting for user confirmation\"}"

# Test task.end
echo "=== Test 5: Task End ==="
send_request "task.end" "{\"session_id\":\"${SESSION_ID}\",\"status\":\"completed\",\"description\":\"Task completed successfully\"}"

# Test invalid method
echo "=== Test 6: Invalid Method ==="
send_request "invalid.method" "null"

# Test session not found
echo "=== Test 7: Session Not Found ==="
send_request "task.update" "{\"session_id\":\"nonexistent-session\",\"status\":\"running\"}"

echo "================================"
echo "Tests completed!"
echo "================================"
