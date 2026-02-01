use std::{
    path::{Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant},
};

use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    webview::WebviewWindowBuilder,
    AppHandle, Manager, WebviewUrl,
};
use tauri_plugin_positioner::{Position, WindowExt};
use tokio::time::sleep;
use tracing::{debug, warn};

use crate::{
    models::{Task, TaskStatus},
    state::AppState,
};

const FRAME_COUNT: usize = 8;
const RUNNING_DIR: &str = "tray/running";
const WAITING_DIR: &str = "tray/waiting";
const RELOAD_INTERVAL: Duration = Duration::from_secs(5);
const RUNNING_FRAME_DELAY: Duration = Duration::from_millis(120);
const WAITING_FRAME_DELAY: Duration = Duration::from_millis(400);
const IDLE_FRAME_DELAY: Duration = Duration::from_millis(1000);

const DEFAULT_RUNNING_FRAMES: [&[u8]; FRAME_COUNT] = [
    include_bytes!("../icons/tray/running/frame_0.png"),
    include_bytes!("../icons/tray/running/frame_1.png"),
    include_bytes!("../icons/tray/running/frame_2.png"),
    include_bytes!("../icons/tray/running/frame_3.png"),
    include_bytes!("../icons/tray/running/frame_4.png"),
    include_bytes!("../icons/tray/running/frame_5.png"),
    include_bytes!("../icons/tray/running/frame_6.png"),
    include_bytes!("../icons/tray/running/frame_7.png"),
];

const DEFAULT_WAITING_FRAMES: [&[u8]; FRAME_COUNT] = [
    include_bytes!("../icons/tray/waiting/frame_0.png"),
    include_bytes!("../icons/tray/waiting/frame_1.png"),
    include_bytes!("../icons/tray/waiting/frame_2.png"),
    include_bytes!("../icons/tray/waiting/frame_3.png"),
    include_bytes!("../icons/tray/waiting/frame_4.png"),
    include_bytes!("../icons/tray/waiting/frame_5.png"),
    include_bytes!("../icons/tray/waiting/frame_6.png"),
    include_bytes!("../icons/tray/waiting/frame_7.png"),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TrayMode {
    Idle,
    Running,
    Waiting,
}

/// Setup tray icon
pub fn setup_tray(app: &tauri::App) -> tauri::Result<()> {
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&quit])?;

    TrayIconBuilder::with_id("main")
        .icon(app.default_window_icon().unwrap().clone())
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| {
            if event.id().as_ref() == "quit" {
                app.exit(0);
            }
        })
        .on_tray_icon_event(|tray, event| {
            let app = tray.app_handle();

            // Update tray position for the positioner plugin
            tauri_plugin_positioner::on_tray_event(app, &event);

            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                toggle_window(app);
            }
        })
        .build(app)?;

    start_tray_animation(app);

    Ok(())
}

/// Toggle window visibility
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
        // Create window if it doesn't exist
        create_main_window(app);
    }
}

/// Create main window
fn create_main_window(app: &AppHandle) {
    let window = WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
        .title("AgentPulse")
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

fn start_tray_animation(app: &tauri::App) {
    let app_handle = app.handle().clone();
    let state = app.state::<Arc<AppState>>().inner().clone();

    tauri::async_runtime::spawn(async move {
        run_tray_animation(app_handle, state).await;
    });
}

async fn run_tray_animation(app_handle: AppHandle, state: Arc<AppState>) {
    let mut last_mode = TrayMode::Idle;
    let mut frame_index = 0usize;
    let mut last_reload = Instant::now() - RELOAD_INTERVAL;
    let mut last_tooltip = String::new();

    let (running_dir, waiting_dir) = match ensure_animation_frames(&app_handle) {
        Ok(dirs) => dirs,
        Err(err) => {
            warn!(error = %err, "Failed to initialize tray animation assets");
            return;
        }
    };

    let mut running_frames = load_frames(&running_dir, &DEFAULT_RUNNING_FRAMES);
    let mut waiting_frames = load_frames(&waiting_dir, &DEFAULT_WAITING_FRAMES);

    loop {
        let tasks = state.get_all_tasks();
        let (mode, summary) = derive_tray_mode(&tasks);

        if last_reload.elapsed() >= RELOAD_INTERVAL {
            running_frames = load_frames(&running_dir, &DEFAULT_RUNNING_FRAMES);
            waiting_frames = load_frames(&waiting_dir, &DEFAULT_WAITING_FRAMES);
            last_reload = Instant::now();
        }

        let Some(tray) = app_handle.tray_by_id("main") else {
            sleep(IDLE_FRAME_DELAY).await;
            continue;
        };

        let tooltip = build_tooltip(&summary);
        if tooltip != last_tooltip {
            if let Err(err) = tray.set_tooltip(Some(tooltip.clone())) {
                debug!(error = %err, "Failed to update tray tooltip");
            }
            last_tooltip = tooltip;
        }

        if mode != last_mode {
            frame_index = 0;
            last_mode = mode;
        }

        match mode {
            TrayMode::Running => {
                if running_frames.is_empty() {
                    frame_index = 0;
                    sleep(RUNNING_FRAME_DELAY).await;
                    continue;
                }
                if let Some(frame) = running_frames.get(frame_index % running_frames.len()) {
                    if let Err(err) = tray.set_icon(Some(frame.clone())) {
                        debug!(error = %err, "Failed to update running tray icon");
                    }
                    frame_index = frame_index.wrapping_add(1);
                }
                sleep(RUNNING_FRAME_DELAY).await;
            }
            TrayMode::Waiting => {
                if waiting_frames.is_empty() {
                    frame_index = 0;
                    sleep(WAITING_FRAME_DELAY).await;
                    continue;
                }
                if let Some(frame) = waiting_frames.get(frame_index % waiting_frames.len()) {
                    if let Err(err) = tray.set_icon(Some(frame.clone())) {
                        debug!(error = %err, "Failed to update waiting tray icon");
                    }
                    frame_index = frame_index.wrapping_add(1);
                }
                sleep(WAITING_FRAME_DELAY).await;
            }
            TrayMode::Idle => {
                if let Some(frame) = running_frames.first() {
                    if let Err(err) = tray.set_icon(Some(frame.clone())) {
                        debug!(error = %err, "Failed to update idle tray icon");
                    }
                }
                sleep(IDLE_FRAME_DELAY).await;
            }
        }
    }
}

fn derive_tray_mode(tasks: &[Task]) -> (TrayMode, TraySummary) {
    let waiting = tasks
        .iter()
        .filter(|task| task.status == TaskStatus::WaitingForInput)
        .count();
    let running = tasks
        .iter()
        .filter(|task| task.status == TaskStatus::Running)
        .count();

    let summary = TraySummary { waiting, running };

    if waiting > 0 {
        (TrayMode::Waiting, summary)
    } else if running > 0 {
        (TrayMode::Running, summary)
    } else {
        (TrayMode::Idle, summary)
    }
}

#[derive(Debug, Clone, Copy)]
struct TraySummary {
    waiting: usize,
    running: usize,
}

fn build_tooltip(summary: &TraySummary) -> String {
    if summary.waiting > 0 {
        format!(
            "Waiting for input ({}) · Running ({})",
            summary.waiting, summary.running
        )
    } else if summary.running > 0 {
        format!("Running ({})", summary.running)
    } else {
        "No active tasks".to_string()
    }
}

fn ensure_animation_frames(app_handle: &AppHandle) -> tauri::Result<(PathBuf, PathBuf)> {
    let base_dir = app_handle.path().app_data_dir()?;
    let running_dir = base_dir.join(RUNNING_DIR);
    let waiting_dir = base_dir.join(WAITING_DIR);

    std::fs::create_dir_all(&running_dir)?;
    std::fs::create_dir_all(&waiting_dir)?;

    write_missing_frames(&running_dir, &DEFAULT_RUNNING_FRAMES)?;
    write_missing_frames(&waiting_dir, &DEFAULT_WAITING_FRAMES)?;

    Ok((running_dir, waiting_dir))
}

fn write_missing_frames(dir: &Path, defaults: &[&[u8]]) -> tauri::Result<()> {
    for (index, bytes) in defaults.iter().enumerate() {
        let path = dir.join(format!("frame_{}.png", index));
        if path.exists() {
            continue;
        }
        std::fs::write(path, bytes)?;
    }
    Ok(())
}

fn load_frames(dir: &Path, defaults: &[&[u8]]) -> Vec<tauri::image::Image<'static>> {
    let mut frames = Vec::with_capacity(FRAME_COUNT);

    for index in 0..FRAME_COUNT {
        let path = dir.join(format!("frame_{}.png", index));
        match tauri::image::Image::from_path(&path) {
            Ok(image) => frames.push(image.to_owned()),
            Err(err) => {
                debug!(
                    error = %err,
                    path = %path.display(),
                    "Failed to load tray frame, falling back to defaults"
                );
                frames.clear();
                break;
            }
        }
    }

    if frames.len() == FRAME_COUNT {
        return frames;
    }

    defaults
        .iter()
        .filter_map(|bytes| tauri::image::Image::from_bytes(bytes).ok())
        .map(|image| image.to_owned())
        .collect()
}
