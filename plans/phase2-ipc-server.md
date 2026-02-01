# Phase 2: IPC Server - Detailed Design

## Overview
Design and implement a Unix Domain Socket server that receives events from Claude Code / Codex.

## 1. socket_server.rs design

### 1.1 Structs
```rust
/// Socket server config
pub struct SocketServerConfig {
    pub socket_path: PathBuf,
}

/// Socket server
pub struct SocketServer {
    app_handle: AppHandle,
    state: Arc<AppState>,
    notification: Arc<NotificationManager>,
    config: SocketServerConfig,
}
```

### 1.2 Listener startup
- Delete existing socket file
- Bind `UnixListener`
- Set permissions to owner only (0600)
- Accept incoming connections in a loop

### 1.3 Handling client connections
- Read line-delimited JSON
- Parse as JSON-RPC
- Dispatch by method name
- Write a JSON-RPC response

### 1.4 Error handling
- Invalid JSON → parse error
- Invalid method → method not found
- Invalid params → invalid params
- Socket errors → log and continue when possible

## 2. JSON-RPC protocol

### 2.1 Request/response structures
```json
{ "jsonrpc": "2.0", "method": "task.start", "params": { ... }, "id": 1 }
{ "jsonrpc": "2.0", "result": { ... }, "id": 1 }
{ "jsonrpc": "2.0", "error": { "code": -32600, "message": "Invalid Request" }, "id": 1 }
```

### 2.2 Supported methods
| Method | Description | Params |
|--------|-------------|--------|
| `task.start` | Start a new session | `TaskStartParams` |
| `task.update` | Update session state | `TaskUpdateParams` |
| `task.end` | End a session | `TaskEndParams` |
| `ping` | Health check | none |

## 3. Parameter models

```rust
pub struct TaskStartParams {
    pub session_id: String,
    pub source: AgentSource,
    pub project_path: String,
}

pub struct TaskUpdateParams {
    pub session_id: String,
    pub status: TaskStatus,
    pub current_tool: Option<String>,
    pub description: Option<String>,
}

pub struct TaskEndParams {
    pub session_id: String,
    pub status: TaskStatus,
    pub description: Option<String>,
}
```

## 4. Event flow

1. Receive JSON-RPC via socket
2. Update `AppState`
3. Emit `tasks-updated` event to frontend
4. Trigger notification when needed

## 5. Validation

- Connect with `nc -U /tmp/agentpulse.sock`
- Send `ping` request and verify response
- Send `task.start/update/end` and verify UI updates

