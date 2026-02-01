# Phase 5: CLI Tool Integration - Detailed Design

## Overview
Implement scripts and setup guides to forward Claude Code and Codex events to AgentPulse.

## 1. Prerequisites
- `jq` for JSON parsing
- `nc` (netcat) for Unix sockets

```bash
brew install jq  # macOS
# nc is bundled on macOS
```

## 2. Claude Code hooks

### File layout
```
scripts/
├── claude-code-hook.sh
└── install-claude-hooks.sh
```

### Behavior
- Read JSON from stdin
- Map events to JSON-RPC
- Send to `/tmp/agentpulse.sock`

## 3. Codex notify

### File layout
```
scripts/
├── codex-notify.sh
└── install-codex-notify.sh
```

### Behavior
- Read JSON from argument or stdin
- Map events to JSON-RPC
- Send to `/tmp/agentpulse.sock`

## 4. Input specs

### Claude Code input
- `session_id`, `cwd`, `tool_name`, `tool_input`, `tool_error`, etc.

### Codex input
- `type` or `event`
- `thread_id` / `session_id`
- `cwd`

## 5. User setup guide

### Claude Code
- Install hooks via `./scripts/install-claude-hooks.sh`
- Or manually update `~/.claude/settings.json`

### Codex
- Install notify via `./scripts/install-codex-notify.sh`
- Or manually update `~/.codex/config.toml`

## 6. Tests

### Unit test script
```bash
./scripts/test-hooks.sh
```

### Integration test steps
1. Start AgentPulse
2. Run `./scripts/test-hooks.sh`
3. Verify tasks appear in the menu bar UI

## 7. Error cases
- Socket missing → exit silently
- Empty input → exit silently
- Invalid JSON → ignore
- Unknown event → ignore

## 8. Implementation checklist
- Create scripts directory
- Implement hook scripts
- Implement installers
- Add test script
- Update README
