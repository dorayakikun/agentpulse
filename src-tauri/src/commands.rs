use crate::protocol::TaskEventPayload;
use crate::state::AppState;
use std::sync::Arc;
use tauri::State;

/// Get all tasks (returns frontend-friendly format with Unix timestamps)
#[tauri::command]
pub fn get_tasks(state: State<Arc<AppState>>) -> Vec<TaskEventPayload> {
    state
        .get_all_tasks()
        .iter()
        .map(|t| TaskEventPayload {
            session_id: t.session_id.clone(),
            source: t.source.as_snake_case().to_string(),
            status: t.status.as_snake_case().to_string(),
            current_tool: t.current_tool.clone(),
            description: t.description.clone(),
            project_path: t.project_path.clone(),
            started_at: t.started_at.timestamp(),
            last_updated: t.last_updated.timestamp(),
        })
        .collect()
}

/// Remove a task
#[tauri::command]
pub fn remove_task(session_id: String, state: State<Arc<AppState>>) -> bool {
    state.remove_task(&session_id).is_some()
}
