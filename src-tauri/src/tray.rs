use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, TrayIconBuilder, TrayIconEvent},
    webview::WebviewWindowBuilder,
    AppHandle, Manager, WebviewUrl,
};
use tauri_plugin_positioner::{Position, WindowExt};

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

            if let TrayIconEvent::Click { button, .. } = event {
                if button == MouseButton::Left {
                    toggle_window(app);
                }
            }
        })
        .build(app)?;

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
