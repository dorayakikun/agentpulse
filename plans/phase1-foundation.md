# Phase 1: Foundation - Detailed Plan

## Overview
Build the foundation for a macOS menu bar app using Tauri 2.0.

## Prerequisites
- Node.js 18+
- npm 8+
- Rust 1.70+

```bash
node --version   # v18+
npm --version    # v8+
rustc --version  # 1.70+
```

## Step 1: Project initialization

### 1.1 Create Tauri project
```bash
npm create tauri-app@latest
```

**Selected options:**
- Framework: React
- Bundler: Vite
- App name: AgentPulse

### 1.2 Install extra packages
```bash
# Tauri plugins
npm install @tauri-apps/plugin-notification @tauri-apps/plugin-positioner
```

## Step 2: Cargo.toml configuration

```toml
[dependencies]
tauri = { version = "2", features = [] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
dashmap = "5"
uuid = { version = "1", features = ["v4"] }
```

## Step 3: tauri.conf.json configuration

**Key points:**
- `windows: []` - no window at startup (menu bar only)
- `trayIcon.iconAsTemplate: true` - macOS dark/light support
- Enable notification and positioner plugins

## Step 4: Capabilities configuration

- Define `default` capabilities
- Add a dev-only capability for localhost access (see Phase 0 changes)

## Step 5: Data model implementation

```rust
/// Agent types
pub enum AgentSource { ClaudeCode, Codex }

/// Task status
pub enum TaskStatus {
    Running,
    WaitingForInput,
    Completed,
    Error,
}

/// Task info
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

## Step 6: State management

- Store all tasks in `AppState`
- Provide APIs to add/update/remove tasks
- Cleanup completed tasks older than 5 minutes

## Step 7: Main entry point

- Initialize logging
- Setup tray
- Spawn socket server
- Register Tauri commands

## Step 8: Tray icon

- Use 8-frame PNG animations
- Support `running`, `waiting`, and `idle`
- Auto-reload assets

## Step 9: Commands

- `get_tasks` returns all tasks
- `remove_task` removes by `session_id`

## Step 10: Validation

### 10.1 Build checks
```bash
npm run tauri dev
npm run tauri build
```

### 10.2 Checklist

| Item | Expected |
| ------ | ---------- |
| Menu bar | Icon is visible |
| Left click | Popover shows |
| Second click | Popover hides |
| Right click | "Quit" menu appears |
| Quit | App exits |
| Dock | No icon shown (macOS) |

## Deliverables

| File | Purpose |
| ------ | --------- |
| `src-tauri/Cargo.toml` | Rust dependencies |
| `src-tauri/tauri.conf.json` | Tauri config |
| `src-tauri/capabilities/default.json` | Capabilities |
| `src-tauri/src/main.rs` | Entry point |
| `src-tauri/src/models.rs` | Data models |
| `src-tauri/src/state.rs` | State management |
| `src-tauri/src/tray.rs` | Tray icon |
| `src-tauri/src/commands.rs` | Tauri commands |

## Next phase
Phase 2 adds:
- `src-tauri/src/socket_server.rs` - Unix Domain Socket server
- `src-tauri/src/notification.rs` - OS notification handling
