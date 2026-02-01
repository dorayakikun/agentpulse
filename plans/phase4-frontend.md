# Phase 4: Frontend - Detailed Plan

## Overview
Build the task list UI and connect it to the backend events.

## UI structure
- Task list view
- Task item row
- Status badge

## Components
- `TaskList.tsx`: list container
- `TaskItem.tsx`: individual row
- `StatusBadge.tsx`: status indicator

## Behavior
- Show tasks in real time
- Visual distinction between Claude Code and Codex (icon + color)
- Allow dismissing tasks

## State
- Fetch tasks from Tauri `get_tasks`
- Subscribe to `tasks-updated` events
- Retry on failure with backoff

## Tests
- Mock `@tauri-apps/api` in E2E tests
- Verify list updates on events
- Verify dismiss behavior
