# Phase 3: 通知機能実装 - 詳細設計

## 概要

macOS ネイティブ通知機能の実装計画。タスク完了時・入力待ち時に通知を表示する。

---

## 1. notification.rs の詳細設計

### 1.1 データ構造

```rust
// src-tauri/src/notification.rs

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::{Duration, Instant};
use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;

use crate::models::AgentSource;

/// 通知の種類
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum NotificationType {
    /// タスク完了通知
    TaskCompleted,
    /// 入力待ち通知（パーミッション要求など）
    WaitingForInput,
}

impl NotificationType {
    pub fn display_name(&self) -> &'static str {
        match self {
            NotificationType::TaskCompleted => "Task Completed",
            NotificationType::WaitingForInput => "Input Required",
        }
    }
}

/// 通知リクエスト
#[derive(Debug, Clone)]
pub struct NotificationRequest {
    pub notification_type: NotificationType,
    pub source: AgentSource,
    pub session_id: String,
    pub project_path: String,
    pub message: Option<String>,
}

/// 通知設定
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NotificationSettings {
    pub enabled: bool,
    pub sound_enabled: bool,
    pub task_completed_enabled: bool,
    pub waiting_for_input_enabled: bool,
    pub rate_limit_seconds: u64,
}

impl Default for NotificationSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            sound_enabled: true,
            task_completed_enabled: true,
            waiting_for_input_enabled: true,
            rate_limit_seconds: 5,
        }
    }
}

/// 通知エラー
#[derive(Debug, thiserror::Error)]
pub enum NotificationError {
    #[error("Failed to send notification: {0}")]
    SendFailed(String),
    #[error("Notification permission denied")]
    PermissionDenied,
}
```

### 1.2 レート制限

```rust
/// 通知レート制限の状態管理
struct NotificationRateLimiter {
    last_notification: RwLock<HashMap<String, Instant>>,
    rate_limit_duration: RwLock<Duration>,
}

impl NotificationRateLimiter {
    fn new(rate_limit_seconds: u64) -> Self {
        Self {
            last_notification: RwLock::new(HashMap::new()),
            rate_limit_duration: RwLock::new(Duration::from_secs(rate_limit_seconds)),
        }
    }

    fn check_and_update(&self, session_id: &str) -> bool {
        let now = Instant::now();
        let rate_limit = *self.rate_limit_duration.read().unwrap();

        // 読み取りロックで確認
        {
            let last_notifications = self.last_notification.read().unwrap();
            if let Some(last_time) = last_notifications.get(session_id) {
                if now.duration_since(*last_time) < rate_limit {
                    return false;
                }
            }
        }

        // 書き込みロックで更新
        {
            let mut last_notifications = self.last_notification.write().unwrap();
            last_notifications.insert(session_id.to_string(), now);
        }

        true
    }

    fn cleanup_session(&self, session_id: &str) {
        let mut last_notifications = self.last_notification.write().unwrap();
        last_notifications.remove(session_id);
    }
}
```

### 1.3 通知マネージャー

```rust
/// 通知マネージャー
pub struct NotificationManager {
    settings: RwLock<NotificationSettings>,
    rate_limiter: NotificationRateLimiter,
}

impl NotificationManager {
    pub fn new() -> Self {
        let settings = NotificationSettings::default();
        let rate_limiter = NotificationRateLimiter::new(settings.rate_limit_seconds);
        Self {
            settings: RwLock::new(settings),
            rate_limiter,
        }
    }

    pub fn send_notification(
        &self,
        app: &AppHandle,
        request: NotificationRequest,
    ) -> Result<(), NotificationError> {
        if !self.should_send_notification(&request) {
            return Ok(());
        }

        let settings = self.settings.read().unwrap();
        let title = self.build_title(&request);
        let body = self.build_body(&request);

        let mut builder = app.notification().builder();
        builder = builder.title(&title).body(&body);

        if settings.sound_enabled {
            builder = builder.sound("default");
        }

        builder
            .show()
            .map_err(|e| NotificationError::SendFailed(e.to_string()))?;

        Ok(())
    }

    fn build_title(&self, request: &NotificationRequest) -> String {
        let source_prefix = match request.source {
            AgentSource::ClaudeCode => "🟣 Claude Code",
            AgentSource::Codex => "🟢 Codex",
        };
        format!("{} - {}", source_prefix, request.notification_type.display_name())
    }

    fn build_body(&self, request: &NotificationRequest) -> String {
        let project_name = std::path::Path::new(&request.project_path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(&request.project_path);

        let base_message = match request.notification_type {
            NotificationType::TaskCompleted => format!("Task completed in {}", project_name),
            NotificationType::WaitingForInput => format!("Waiting for input in {}", project_name),
        };

        match &request.message {
            Some(msg) if !msg.is_empty() => format!("{}\n{}", base_message, msg),
            _ => base_message,
        }
    }
}
```

---

## 2. 通知トリガーのタイミング

### 2.1 イベントマッピング

| ソース | イベント | 通知種別 | 説明 |
|--------|----------|----------|------|
| Claude Code | `SessionEnd` (reason: exit) | `TaskCompleted` | セッション正常終了 |
| Claude Code | `Notification` (type: permission_prompt) | `WaitingForInput` | パーミッション要求 |
| Claude Code | `Notification` (type: idle_prompt) | `WaitingForInput` | 60秒以上アイドル状態 |
| Codex | `agent-turn-complete` | `TaskCompleted` | ターン完了 |
| Codex | `approval-requested` | `WaitingForInput` | 承認要求 |

### 2.2 socket_server.rs との連携

```rust
// socket_server.rs（通知関連の追記部分）

/// Claude Code からのイベントを処理
fn handle_claude_code_event(
    app: &AppHandle,
    notification_manager: &Arc<NotificationManager>,
    event: &ClaudeCodeEvent,
) {
    match event {
        ClaudeCodeEvent::SessionEnd { session_id, project_path, reason } => {
            if reason == "exit" || reason == "other" {
                let request = NotificationRequest {
                    notification_type: NotificationType::TaskCompleted,
                    source: AgentSource::ClaudeCode,
                    session_id: session_id.clone(),
                    project_path: project_path.clone(),
                    message: None,
                };
                let _ = notification_manager.send_notification(app, request);
                notification_manager.cleanup_session(session_id);
            }
        }
        ClaudeCodeEvent::Notification { session_id, project_path, notification_type, message } => {
            if notification_type == "permission_prompt" || notification_type == "idle_prompt" {
                let request = NotificationRequest {
                    notification_type: NotificationType::WaitingForInput,
                    source: AgentSource::ClaudeCode,
                    session_id: session_id.clone(),
                    project_path: project_path.clone(),
                    message: Some(message.clone()),
                };
                let _ = notification_manager.send_notification(app, request);
            }
        }
        _ => {}
    }
}

/// Codex からのイベントを処理
fn handle_codex_event(
    app: &AppHandle,
    notification_manager: &Arc<NotificationManager>,
    event: &CodexEvent,
) {
    match event.event_type.as_str() {
        "agent-turn-complete" => {
            let request = NotificationRequest {
                notification_type: NotificationType::TaskCompleted,
                source: AgentSource::Codex,
                session_id: event.thread_id.clone(),
                project_path: event.cwd.clone(),
                message: event.last_assistant_message.clone(),
            };
            let _ = notification_manager.send_notification(app, request);
        }
        "approval-requested" => {
            let request = NotificationRequest {
                notification_type: NotificationType::WaitingForInput,
                source: AgentSource::Codex,
                session_id: event.thread_id.clone(),
                project_path: event.cwd.clone(),
                message: Some("Codex is waiting for your approval".to_string()),
            };
            let _ = notification_manager.send_notification(app, request);
        }
        _ => {}
    }
}
```

---

## 3. 通知内容のフォーマット

### 3.1 タイトルフォーマット

| ソース | 通知種別 | タイトル例 |
|--------|----------|-----------|
| Claude Code | Task Completed | `🟣 Claude Code - Task Completed` |
| Claude Code | Input Required | `🟣 Claude Code - Input Required` |
| Codex | Task Completed | `🟢 Codex - Task Completed` |
| Codex | Input Required | `🟢 Codex - Input Required` |

### 3.2 本文フォーマット

```
[基本メッセージ]
Task completed in [プロジェクト名]

または

Waiting for input in [プロジェクト名]
[追加メッセージ（あれば）]
```

---

## 4. ユーザー設定（将来の拡張性）

### 4.1 設定保存

```rust
// src-tauri/src/settings.rs

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use crate::notification::NotificationSettings;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    pub notification: NotificationSettings,
    pub socket_path: String,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            notification: NotificationSettings::default(),
            socket_path: "/tmp/ai-agent-status.sock".to_string(),
        }
    }
}

impl AppSettings {
    pub fn config_path() -> PathBuf {
        dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("ai-agent-status")
            .join("settings.json")
    }

    pub fn load() -> Self {
        let path = Self::config_path();
        if path.exists() {
            std::fs::read_to_string(&path)
                .ok()
                .and_then(|content| serde_json::from_str(&content).ok())
                .unwrap_or_default()
        } else {
            Self::default()
        }
    }

    pub fn save(&self) -> Result<(), std::io::Error> {
        let path = Self::config_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(path, content)
    }
}
```

---

## 5. Tauri プラグイン設定

### 5.1 Cargo.toml

```toml
[dependencies]
tauri = { version = "2.0", features = ["tray-icon"] }
tauri-plugin-notification = "2.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1", features = ["full"] }
log = "0.4"
thiserror = "1.0"
dirs = "5.0"
dashmap = "6.0"
uuid = { version = "1.0", features = ["v4"] }
```

### 5.2 capabilities/default.json

```json
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "default",
  "description": "Default capability for AI Agent Status Monitor",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "core:window:allow-close",
    "core:window:allow-hide",
    "core:window:allow-show",
    "notification:default",
    "notification:allow-is-permission-granted",
    "notification:allow-request-permission",
    "notification:allow-notify",
    "notification:allow-show"
  ]
}
```

### 5.3 lib.rs への統合

```rust
// src-tauri/src/lib.rs

mod commands;
mod models;
mod notification;
mod settings;
mod socket_server;
mod state;
mod tray;

use notification::NotificationManager;
use settings::AppSettings;
use state::AppState;
use std::sync::Arc;

pub fn run() {
    let app_settings = AppSettings::load();
    let notification_manager = Arc::new(NotificationManager::new());
    notification_manager.update_settings(app_settings.notification.clone());

    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .manage(Arc::new(AppState::new()))
        .manage(notification_manager.clone())
        .invoke_handler(tauri::generate_handler![
            commands::get_tasks,
            commands::get_notification_settings,
            commands::update_notification_settings,
        ])
        .setup(move |app| {
            let app_handle = app.handle().clone();
            let notification_mgr = notification_manager.clone();

            tray::setup_tray(&app_handle)?;

            let socket_path = app_settings.socket_path.clone();
            tauri::async_runtime::spawn(async move {
                if let Err(e) = socket_server::start_server(
                    app_handle,
                    notification_mgr,
                    &socket_path,
                ).await {
                    log::error!("Socket server error: {}", e);
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

---

## 6. 実装順序

1. **Step 1**: `Cargo.toml` に `tauri-plugin-notification` を追加
2. **Step 2**: `capabilities/default.json` にパーミッションを追加
3. **Step 3**: `notification.rs` を作成（型定義、NotificationManager）
4. **Step 4**: `settings.rs` を作成（設定保存・読み込み）
5. **Step 5**: `lib.rs` でプラグイン初期化と NotificationManager の登録
6. **Step 6**: `socket_server.rs` に通知トリガーロジックを統合
7. **Step 7**: `commands.rs` に設定変更コマンドを追加
8. **Step 8**: テスト実装

---

## 7. テスト

### 7.1 ユニットテスト

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_notification_settings_default() {
        let settings = NotificationSettings::default();
        assert!(settings.enabled);
        assert!(settings.sound_enabled);
        assert_eq!(settings.rate_limit_seconds, 5);
    }

    #[test]
    fn test_rate_limiter() {
        let limiter = NotificationRateLimiter::new(1);
        assert!(limiter.check_and_update("session1"));
        assert!(!limiter.check_and_update("session1")); // レート制限
        assert!(limiter.check_and_update("session2")); // 別セッションは OK
    }
}
```

### 7.2 手動テスト

```bash
# ソケットにテストメッセージ送信
echo '{"source":"claude_code","event":"session_end","session_id":"test123","cwd":"/tmp/test"}' | nc -U /tmp/ai-agent-status.sock
```

---

## Critical Files

| ファイル | 役割 |
|----------|------|
| `src-tauri/src/notification.rs` | 通知機能のコアロジック |
| `src-tauri/src/settings.rs` | 設定の永続化 |
| `src-tauri/src/socket_server.rs` | 通知トリガーの発火 |
| `src-tauri/src/lib.rs` | プラグイン初期化 |
| `src-tauri/capabilities/default.json` | 通知パーミッション |
| `src-tauri/Cargo.toml` | 依存関係 |
