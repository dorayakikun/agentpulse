# AgentPulse

A macOS menu bar app that tracks and lists the progress of AI agents such as Claude Code and Codex.

## Features

- Check the status of all agents with one click from the menu bar
- Visual distinction between Claude Code and Codex (icons and colors)
- Native OS notifications when tasks complete or when input is needed
- Lightweight, always-on app

## Architecture

```text
┌─────────────────────────────────────────────────┐
│              AgentPulse                         │
│         (Tauri menu bar app)                    │
├─────────────────────────────────────────────────┤
│  Frontend (React)  ◄─IPC─►  Backend (Rust)      │
│  - Task list UI            - State management   │
│                             - Socket server     │
│                             - Notifications     │
└───────────────────────┬─────────────────────────┘
                        │
              Unix Domain Socket
              (/tmp/agentpulse.sock)
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   Claude Code     Claude Code       Codex
    (Hooks)         (Hooks)        (notify)
```

## Requirements

- macOS 12.0+ / Linux
- [Rust](https://www.rust-lang.org/tools/install)
- [Node.js](https://nodejs.org/) 18+
- jq (`brew install jq` / `apt install jq`)

## Development

```bash
# Install dependencies
npm install

# Start dev server
npm run tauri dev

# Build
npm run tauri build
```

## CLI Tool Integration

AgentPulse receives events from Claude Code and Codex and displays task progress in real time.

### Prerequisites

```bash
# Install jq (macOS)
brew install jq

# Install jq (Ubuntu/Debian)
sudo apt-get install jq
```

### Claude Code Setup

```bash
# Automatic install (recommended)
./scripts/install-claude-hooks.sh
```

If you want to configure manually, add the following to `~/.claude/settings.json`:

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

### Codex Setup

```bash
# Automatic install (recommended)
./scripts/install-codex-notify.sh
```

If you want to configure manually, add the following to `~/.codex/config.toml`:

```toml
notify = ["bash", "/path/to/scripts/codex-notify.sh"]
```

### Verification

1. Launch AgentPulse
2. Confirm the menu bar icon appears
3. Run the test script:
   ```bash
   ./scripts/test-hooks.sh
   ```
4. Confirm the test session appears in the task list
5. Start a session in Claude Code or Codex
6. Confirm the session appears in the task list

### E2E Tests (Playwright)

You can run the Web UI tests with the Tauri bridge mocked using `npm test`.

```bash
# Install dependencies
npm install

# Install Playwright browsers (first time only)
npx playwright install

# Run tests
npm test
```

When running Playwright, `VITE_E2E=1` is set automatically and `@tauri-apps/api` is swapped for the mock implementation.

## Troubleshooting

| Problem | Cause | Fix |
| --------- | ------- | ----- |
| Tasks are not shown | Socket not connected | Start the app and check with `ls -la /tmp/agentpulse.sock` |
| jq: command not found | jq not installed | `brew install jq` (macOS) |
| Permission denied | Script is not executable | `chmod +x scripts/*.sh` |
| Settings not applied | Claude Code restart required | Restart Claude Code |

### Codex notify debug log

`scripts/codex-notify.sh` can toggle debug logging on/off.

Enable (single session):
```bash
CODEX_NOTIFY_DEBUG=1 codex "hello"
```

Enable (persistent):
```toml
notify = ["bash", "-lc", "CODEX_NOTIFY_DEBUG=1 /path/to/scripts/codex-notify.sh"]
```

Disable:
```bash
unset CODEX_NOTIFY_DEBUG
```

Log output: `/tmp/codex-notify-debug.log`

### Debugging

```bash
# Check socket connectivity
echo '{"jsonrpc":"2.0","method":"ping","id":1}' | nc -U /tmp/agentpulse.sock

# Send an event manually
echo '{"session_id":"debug-test","cwd":"/tmp"}' | ./scripts/claude-code-hook.sh session_start

# Check log file (macOS)
tail -f ~/Library/Logs/AgentPulse/agentpulse*.log
```

### Tray animation for task state

The tray (menu bar) icon animates using **8 PNGs**.  
There are two sets: `running` and `waiting`, and you can replace them later to customize the animation.

macOS locations:
- `~/Library/Application Support/com.agentpulse.app/tray/running/frame_0.png` ... `frame_7.png`
- `~/Library/Application Support/com.agentpulse.app/tray/waiting/frame_0.png` ... `frame_7.png`

Linux locations (XDG Base Directory):
- `XDG_DATA_HOME` (defaults to `~/.local/share` if unset)
- `XDG_DATA_HOME/com.agentpulse.app/tray/running/frame_0.png` ... `frame_7.png`
- `XDG_DATA_HOME/com.agentpulse.app/tray/waiting/frame_0.png` ... `frame_7.png`

Behavior:
- If `waiting` >= 1: show the `waiting` set
- If `running` >= 1: show the `running` set
- Otherwise: show `running/frame_0.png`

After replacement, assets auto-reload within a few seconds.

## Tech Stack

- **Frontend**: React 18 + TypeScript + Vite
- **Backend**: Rust + Tauri 2.0
- **Transport**: Unix Domain Socket + JSON-RPC
- **Logging**: tracing + tracing-subscriber

## License

MIT
