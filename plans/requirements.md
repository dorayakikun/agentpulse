# AI Agent Status Monitor - Requirements

## Overview
A menu bar app that lists and manages task progress when running multiple Claude Code / Codex sessions.

## Detailed plan files
- **Phase 1**: `./phase1-foundation.md` - Detailed plan for foundation work
- **Phase 2**: `./phase2-ipc-server.md` - Detailed plan for IPC server implementation
- **Phase 3**: `./phase3-notification.md` - Detailed plan for notifications
- **Phase 4**: `./phase4-frontend.md` - Detailed plan for frontend UI
- **Phase 5**: `./phase5-cli-integration.md` - Detailed plan for CLI tool integration
- **Phase 6**: `./phase6-quality.md` - Detailed plan for quality improvements

## Confirmed requirements

| Item | Details |
|------|---------|
| Language/FW | Rust + Tauri 2.0 |
| UI form | macOS menu bar app |
| Supported OS | macOS (primary), Linux/Windows later |
| History storage | Not required (only active tasks) |
| Notifications | Native OS notifications |
| Claude Code integration | Hooks feature |
| Codex integration | notify configuration |

## Architecture

```
┌─────────────────────────────────────────────────┐
│         AI Agent Status Monitor                 │
│         (Tauri menu bar app)                    │
├─────────────────────────────────────────────────┤
│  Frontend (React)  ◄─IPC─►  Backend (Rust)      │
│  - Task list UI            - State management   │
│                             - Socket server     │
│                             - Notifications     │
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

## Directory structure

```
ai-agent-status/
├── src-tauri/
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   └── src/
│       ├── main.rs           # entry point
│       ├── lib.rs            # main library
│       ├── models.rs         # data models
│       ├── state.rs          # state management
│       ├── socket_server.rs  # UDS server
│       ├── notification.rs   # notifications
│       ├── tray.rs           # menu bar
│       └── commands.rs       # Tauri commands
├── src/
│   ├── main.tsx
│   ├── App.tsx               # main UI
│   ├── components/
│   │   ├── TaskList.tsx
│   │   ├── TaskItem.tsx
│   │   └── StatusBadge.tsx
│   └── hooks/
│       └── useTasks.ts
├── scripts/
│   ├── claude-code-hook.sh   # Claude Code hook (Bash)
│   └── codex-notify.sh       # Codex notify (Bash)
├── package.json
└── README.md
```

## Key data models

```rust
pub enum AgentSource { ClaudeCode, Codex }

pub enum TaskStatus {
    Running,           // running
    WaitingForInput,   // waiting for input
    Completed,         // completed
    Error,             // error
}

pub struct Task {
    session_id: String,
    source: AgentSource,
    status: TaskStatus,
    current_tool: Option<String>,
    description: Option<String>,
    project_path: String,
    started_at: SystemTime,
    last_updated: SystemTime,
}
```

## Development steps

### Phase 1: Foundation
1. Create the project with `npm create tauri-app@latest`
2. Configure menu bar app (`tauri.conf.json`)
3. Implement state management (`state.rs`)

### Phase 2: IPC server
1. Unix Domain Socket server (`socket_server.rs`)
2. Receive events via JSON-RPC
3. Emit Tauri events to the frontend

### Phase 3: Notifications
1. macOS notifications via `tauri-plugin-notification`
2. Notify on task completion and when input is required

### Phase 4: Frontend UI
1. Task list UI in React
2. Visual distinction for Claude Code / Codex (icons, colors)
3. Real-time updates

### Phase 5: CLI tool integration
1. Claude Code hooks scripts
2. Codex notify scripts
3. User setup guide

### Phase 6: Quality improvements
1. Error handling
2. Logging
3. macOS signing and notarization

## CLI tool integration config

### Claude Code (~/.claude/settings.json)
```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "claude-code-hook.sh session_start" }] }],
    "PreToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "claude-code-hook.sh pre_tool" }] }],
    "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "claude-code-hook.sh post_tool" }] }],
    "Notification": [{ "matcher": "permission_prompt|idle_prompt", "hooks": [{ "type": "command", "command": "claude-code-hook.sh notification" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "claude-code-hook.sh session_end" }] }]
  }
}
```

### Codex (~/.codex/config.toml)
```toml
notify = ["bash", "/path/to/codex-notify.sh"]
```

## Notification scripts

Both scripts are standardized on **Bash + jq + nc**. Dependencies: `jq`, `nc` (netcat)

### claude-code-hook.sh
- **Input**: JSON from stdin
- **Processing**: parse with `jq`, build a message per event type
- **Output**: send to socket via `nc -U /tmp/ai-agent-status.sock`

```bash
#!/bin/bash
SOCKET="/tmp/ai-agent-status.sock"
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
# ... build JSON-RPC message based on event type
echo "$MESSAGE" | nc -U "$SOCKET"
```

### codex-notify.sh
- **Input**: JSON in `$1`
- **Processing**: parse with `jq`, build a message per event type
- **Output**: send to socket via `nc -U /tmp/ai-agent-status.sock`

```bash
#!/bin/bash
SOCKET="/tmp/ai-agent-status.sock"
INPUT="$1"
EVENT_TYPE=$(echo "$INPUT" | jq -r '.type // empty')
# ... build JSON-RPC message based on event type
echo "$MESSAGE" | nc -U "$SOCKET"
```

### Install dependencies (macOS)
```bash
brew install jq  # nc is bundled on macOS
```

## Primary crates

| Crate | Purpose |
|-------|---------|
| tauri (2.x) | framework |
| tokio | async runtime |
| serde/serde_json | serialization |
| tauri-plugin-notification | OS notifications |
| dashmap | thread-safe map |
| uuid | session IDs |

## Validation steps

1. **Basic behavior**: launch app → menu bar icon appears → click shows window
2. **Claude Code integration**: configure hooks → run `claude` → tasks appear
3. **Codex integration**: configure notify → run `codex` → tasks appear
4. **Notifications**: macOS notification on completion and waiting for input
5. **Identification**: Claude Code / Codex tasks are visually distinct
