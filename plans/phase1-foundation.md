# Phase 1: 基盤構築 - 詳細計画

## 概要
Tauri 2.0 を使用して macOS メニューバーアプリの基盤を構築する。

## 前提条件

```bash
# 必要なツール
node --version   # v18 以上
npm --version    # v8 以上
rustc --version  # 1.70 以上
cargo --version
```

---

## Step 1: プロジェクト初期化

### 1.1 Tauri プロジェクト作成

```bash
cd /Users/tomohidetakao/go/src/github.com/dorayakikun/ai_agent_status
npm create tauri-app@latest . -- --template react-ts
```

**選択オプション:**
- Project name: `ai-agent-status`
- Package manager: `npm`
- UI template: `React`
- UI flavor: `TypeScript`

### 1.2 追加パッケージのインストール

```bash
# Frontend
npm install

# Tauri プラグイン
npm install @tauri-apps/plugin-notification
npm install @tauri-apps/plugin-positioner
```

---

## Step 2: Cargo.toml の設定

### 2.1 src-tauri/Cargo.toml

```toml
[package]
name = "ai-agent-status"
version = "0.1.0"
description = "AI Agent Status Monitor"
authors = ["you"]
edition = "2021"

[lib]
name = "ai_agent_status_lib"
crate-type = ["staticlib", "cdylib", "rlib"]

[build-dependencies]
tauri-build = { version = "2", features = [] }

[dependencies]
# Tauri コア
tauri = { version = "2", features = ["tray-icon", "image-png"] }
tauri-plugin-shell = "2"
tauri-plugin-notification = "2"
tauri-plugin-positioner = "2"

# 非同期ランタイム
tokio = { version = "1", features = ["full", "net"] }

# シリアライゼーション
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# 状態管理
dashmap = "6"
parking_lot = "0.12"

# ユーティリティ
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
thiserror = "2"
anyhow = "1"
log = "0.4"
env_logger = "0.11"

[target.'cfg(target_os = "macos")'.dependencies]
cocoa = "0.26"
objc = "0.2"
```

---

## Step 3: tauri.conf.json の設定

### 3.1 src-tauri/tauri.conf.json

```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "AI Agent Status",
  "version": "0.1.0",
  "identifier": "com.ai-agent-status.app",
  "build": {
    "beforeDevCommand": "npm run dev",
    "devUrl": "http://localhost:5173",
    "beforeBuildCommand": "npm run build",
    "frontendDist": "../dist"
  },
  "app": {
    "windows": [],
    "security": {
      "csp": null
    },
    "trayIcon": {
      "iconPath": "icons/icon.png",
      "iconAsTemplate": true,
      "id": "main"
    }
  },
  "bundle": {
    "active": true,
    "targets": ["dmg", "app"],
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ],
    "macOS": {
      "minimumSystemVersion": "10.15"
    }
  },
  "plugins": {
    "notification": {
      "all": true
    },
    "positioner": {
      "all": true
    }
  }
}
```

**重要ポイント:**
- `windows: []` - 起動時ウィンドウなし（メニューバーのみ）
- `trayIcon.iconAsTemplate: true` - macOS のダーク/ライトモード対応
- `plugins` - 通知とポジショナーを有効化

---

## Step 4: Capabilities 設定

### 4.1 src-tauri/capabilities/default.json

```json
{
  "$schema": "https://raw.githubusercontent.com/tauri-apps/tauri/refs/heads/v2/crates/tauri-utils/schema.json",
  "identifier": "default",
  "description": "Default permissions for the app",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "core:window:allow-show",
    "core:window:allow-hide",
    "core:window:allow-set-focus",
    "core:window:allow-close",
    "shell:allow-open",
    "notification:default",
    "notification:allow-is-permission-granted",
    "notification:allow-request-permission",
    "notification:allow-notify",
    "positioner:default"
  ]
}
```

---

## Step 5: データモデル実装

### 5.1 src-tauri/src/models.rs

```rust
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// エージェントの種類
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum AgentSource {
    ClaudeCode,
    Codex,
}

impl std::fmt::Display for AgentSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AgentSource::ClaudeCode => write!(f, "Claude Code"),
            AgentSource::Codex => write!(f, "Codex"),
        }
    }
}

/// タスクのステータス
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Running,
    WaitingForInput,
    Completed,
    Error,
}

impl std::fmt::Display for TaskStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TaskStatus::Running => write!(f, "Running"),
            TaskStatus::WaitingForInput => write!(f, "Waiting for Input"),
            TaskStatus::Completed => write!(f, "Completed"),
            TaskStatus::Error => write!(f, "Error"),
        }
    }
}

/// タスク情報
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub session_id: String,
    pub source: AgentSource,
    pub status: TaskStatus,
    pub current_tool: Option<String>,
    pub description: Option<String>,
    pub project_path: String,
    pub started_at: DateTime<Utc>,
    pub last_updated: DateTime<Utc>,
}

impl Task {
    pub fn new(session_id: String, source: AgentSource, project_path: String) -> Self {
        let now = Utc::now();
        Self {
            session_id,
            source,
            status: TaskStatus::Running,
            current_tool: None,
            description: None,
            project_path,
            started_at: now,
            last_updated: now,
        }
    }

    pub fn update_status(&mut self, status: TaskStatus) {
        self.status = status;
        self.last_updated = Utc::now();
    }

    pub fn update_tool(&mut self, tool: Option<String>, description: Option<String>) {
        self.current_tool = tool;
        self.description = description;
        self.last_updated = Utc::now();
    }
}

/// 外部から受信するイベント（JSON-RPC params）
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum AgentEvent {
    SessionStart {
        session_id: String,
        source: AgentSource,
        cwd: String,
    },
    ToolStart {
        session_id: String,
        tool_name: String,
        description: Option<String>,
    },
    ToolEnd {
        session_id: String,
        tool_name: String,
        success: bool,
    },
    WaitingForInput {
        session_id: String,
        message: String,
    },
    SessionEnd {
        session_id: String,
    },
    AgentTurnComplete {
        session_id: String,
        description: Option<String>,
    },
}
```

---

## Step 6: 状態管理実装

### 6.1 src-tauri/src/state.rs

```rust
use crate::models::{AgentEvent, AgentSource, Task, TaskStatus};
use chrono::Utc;
use dashmap::DashMap;
use std::sync::Arc;

/// アプリケーション状態
#[derive(Debug, Clone)]
pub struct AppState {
    tasks: Arc<DashMap<String, Task>>,
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

impl AppState {
    pub fn new() -> Self {
        Self {
            tasks: Arc::new(DashMap::new()),
        }
    }

    /// 全タスクを取得
    pub fn get_all_tasks(&self) -> Vec<Task> {
        self.tasks
            .iter()
            .map(|entry| entry.value().clone())
            .collect()
    }

    /// タスクを取得
    pub fn get_task(&self, session_id: &str) -> Option<Task> {
        self.tasks.get(session_id).map(|t| t.clone())
    }

    /// イベントを処理
    pub fn handle_event(&self, event: AgentEvent) -> Option<Task> {
        match event {
            AgentEvent::SessionStart {
                session_id,
                source,
                cwd,
            } => {
                let task = Task::new(session_id.clone(), source, cwd);
                self.tasks.insert(session_id, task.clone());
                Some(task)
            }

            AgentEvent::ToolStart {
                session_id,
                tool_name,
                description,
            } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    task.update_tool(Some(tool_name), description);
                    task.update_status(TaskStatus::Running);
                    return Some(task.clone());
                }
                None
            }

            AgentEvent::ToolEnd {
                session_id,
                tool_name: _,
                success,
            } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    task.update_tool(None, None);
                    if !success {
                        task.update_status(TaskStatus::Error);
                    }
                    return Some(task.clone());
                }
                None
            }

            AgentEvent::WaitingForInput {
                session_id,
                message,
            } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    task.update_status(TaskStatus::WaitingForInput);
                    task.description = Some(message);
                    task.last_updated = Utc::now();
                    return Some(task.clone());
                }
                None
            }

            AgentEvent::SessionEnd { session_id } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    task.update_status(TaskStatus::Completed);
                    return Some(task.clone());
                }
                None
            }

            AgentEvent::AgentTurnComplete {
                session_id,
                description,
            } => {
                if let Some(mut task) = self.tasks.get_mut(&session_id) {
                    task.description = description;
                    task.last_updated = Utc::now();
                    return Some(task.clone());
                }
                None
            }
        }
    }

    /// 完了タスクをクリーンアップ（5分以上経過）
    pub fn cleanup_completed_tasks(&self) {
        let now = Utc::now();
        let timeout = chrono::Duration::minutes(5);

        self.tasks.retain(|_, task| {
            match task.status {
                TaskStatus::Completed | TaskStatus::Error => {
                    now.signed_duration_since(task.last_updated) < timeout
                }
                _ => true,
            }
        });
    }

    /// タスクを削除
    pub fn remove_task(&self, session_id: &str) -> Option<Task> {
        self.tasks.remove(session_id).map(|(_, task)| task)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_lifecycle() {
        let state = AppState::new();

        // セッション開始
        let event = AgentEvent::SessionStart {
            session_id: "test-123".to_string(),
            source: AgentSource::ClaudeCode,
            cwd: "/tmp/project".to_string(),
        };
        let task = state.handle_event(event).unwrap();
        assert_eq!(task.status, TaskStatus::Running);

        // ツール開始
        let event = AgentEvent::ToolStart {
            session_id: "test-123".to_string(),
            tool_name: "Write".to_string(),
            description: Some("Creating file".to_string()),
        };
        let task = state.handle_event(event).unwrap();
        assert_eq!(task.current_tool, Some("Write".to_string()));

        // セッション終了
        let event = AgentEvent::SessionEnd {
            session_id: "test-123".to_string(),
        };
        let task = state.handle_event(event).unwrap();
        assert_eq!(task.status, TaskStatus::Completed);
    }
}
```

---

## Step 7: メインエントリーポイント

### 7.1 src-tauri/src/main.rs

```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod models;
mod state;
mod tray;

use state::AppState;
use tauri::Manager;

#[cfg(target_os = "macos")]
use tauri::ActivationPolicy;

fn main() {
    env_logger::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_shell::init())
        .manage(AppState::new())
        .setup(|app| {
            // macOS でドックアイコンを非表示
            #[cfg(target_os = "macos")]
            app.set_activation_policy(ActivationPolicy::Accessory)?;

            // トレイアイコンをセットアップ
            tray::setup_tray(app)?;

            log::info!("AI Agent Status Monitor started");

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_tasks,
            commands::remove_task,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### 7.2 src-tauri/src/lib.rs

```rust
pub mod commands;
pub mod models;
pub mod state;
pub mod tray;
```

---

## Step 8: トレイアイコン実装

### 8.1 src-tauri/src/tray.rs

```rust
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, TrayIconBuilder, TrayIconEvent},
    webview::WebviewWindowBuilder,
    AppHandle, Manager, WebviewUrl,
};
use tauri_plugin_positioner::{Position, WindowExt};

/// トレイアイコンをセットアップ
pub fn setup_tray(app: &tauri::App) -> tauri::Result<()> {
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&quit])?;

    TrayIconBuilder::with_id("main")
        .icon(app.default_window_icon().unwrap().clone())
        .icon_as_template(true)
        .menu(&menu)
        .menu_on_left_click(false)
        .on_menu_event(|app, event| {
            if event.id().as_ref() == "quit" {
                app.exit(0);
            }
        })
        .on_tray_icon_event(|tray, event| {
            let app = tray.app_handle();

            if let TrayIconEvent::Click { button, .. } = event {
                if button == MouseButton::Left {
                    toggle_window(app);
                }
            }
        })
        .build(app)?;

    Ok(())
}

/// ウィンドウの表示/非表示を切り替え
fn toggle_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            let _ = window.move_window(Position::TrayBottomCenter);
            let _ = window.show();
            let _ = window.set_focus();
        }
    } else {
        // ウィンドウが存在しない場合は作成
        create_main_window(app);
    }
}

/// メインウィンドウを作成
fn create_main_window(app: &AppHandle) {
    let window = WebviewWindowBuilder::new(
        app,
        "main",
        WebviewUrl::App("index.html".into()),
    )
    .title("AI Agent Status")
    .inner_size(400.0, 500.0)
    .decorations(false)
    .skip_taskbar(true)
    .always_on_top(true)
    .visible(false)
    .build();

    if let Ok(window) = window {
        let _ = window.move_window(Position::TrayBottomCenter);
        let _ = window.show();
        let _ = window.set_focus();
    }
}
```

---

## Step 9: コマンド実装

### 9.1 src-tauri/src/commands.rs

```rust
use crate::models::Task;
use crate::state::AppState;
use tauri::State;

/// 全タスクを取得
#[tauri::command]
pub fn get_tasks(state: State<AppState>) -> Vec<Task> {
    state.get_all_tasks()
}

/// タスクを削除
#[tauri::command]
pub fn remove_task(session_id: String, state: State<AppState>) -> Option<Task> {
    state.remove_task(&session_id)
}
```

---

## Step 10: 検証手順

### 10.1 ビルド確認

```bash
cd /Users/tomohidetakao/go/src/github.com/dorayakikun/ai_agent_status

# 開発サーバー起動
npm run tauri dev
```

### 10.2 チェックリスト

| 項目 | 確認内容 |
|------|----------|
| メニューバー | アイコンが表示される |
| 左クリック | ポップオーバーウィンドウが表示される |
| 再クリック | ウィンドウが非表示になる |
| 右クリック | "Quit" メニューが表示される |
| Quit | アプリが終了する |
| Dock | アイコンが表示されない（macOS） |

### 10.3 ユニットテスト

```bash
cd src-tauri
cargo test
```

---

## 成果物一覧

| ファイル | 説明 |
|----------|------|
| `src-tauri/Cargo.toml` | Rust 依存関係 |
| `src-tauri/tauri.conf.json` | Tauri 設定 |
| `src-tauri/capabilities/default.json` | 権限設定 |
| `src-tauri/src/main.rs` | エントリーポイント |
| `src-tauri/src/lib.rs` | ライブラリエクスポート |
| `src-tauri/src/models.rs` | データモデル |
| `src-tauri/src/state.rs` | 状態管理 |
| `src-tauri/src/tray.rs` | トレイアイコン |
| `src-tauri/src/commands.rs` | Tauri コマンド |

---

## 次のフェーズへの準備

Phase 1 完了後、Phase 2（IPC サーバー実装）で以下を追加:
- `src-tauri/src/socket_server.rs` - Unix Domain Socket サーバー
- `src-tauri/src/notification.rs` - OS 通知処理
