# Phase 3: Notifications - Detailed Plan

## Overview
Implement native OS notifications for task completion and waiting-for-input states.

## Goals
- Notify when a task completes
- Notify when a task needs user input
- Rate-limit notifications to avoid spam

## Implementation

### 1. Use Tauri notification plugin
- Add `tauri-plugin-notification`
- Initialize in `main.rs`

### 2. Notification manager
- Centralize notification logic in `notification.rs`
- Provide rate limiting

### 3. Triggers
- On `TaskStatus::Completed` → send completion notification
- On `TaskStatus::WaitingForInput` → send prompt notification

### 4. Payload
- Title: `AgentPulse`
- Body: use task description where possible

## Tests
- Trigger a completion event and verify notification
- Trigger a waiting-for-input event and verify notification
- Validate rate limiting and suppression logs
