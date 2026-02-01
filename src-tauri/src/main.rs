#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod error;
mod logging;
mod models;
mod notification;
mod protocol;
mod socket_server;
mod state;
mod tray;

use std::sync::Arc;

use logging::{get_log_dir, init_logging, LogConfig};
use notification::NotificationManager;
use socket_server::{SocketServer, SocketServerConfig};
use state::AppState;
use tauri::RunEvent;
use tracing::{error, info, Level};

#[cfg(target_os = "macos")]
use tauri::ActivationPolicy;

fn main() {
    // Initialize logging
    let log_config = LogConfig {
        level: if cfg!(debug_assertions) {
            Level::DEBUG
        } else {
            Level::INFO
        },
        log_dir: get_log_dir(),
        json_format: !cfg!(debug_assertions),
    };

    // Hold guard (dropping it will lose logs)
    let _guard = init_logging(log_config);

    info!(
        version = env!("CARGO_PKG_VERSION"),
        "Starting AgentPulse"
    );

    let app_state = Arc::new(AppState::new());
    let notification_manager = Arc::new(NotificationManager::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_shell::init())
        .manage(app_state.clone())
        .manage(notification_manager.clone())
        .setup(move |app| {
            // Hide dock icon on macOS
            #[cfg(target_os = "macos")]
            app.set_activation_policy(ActivationPolicy::Accessory);

            // Setup tray icon
            tray::setup_tray(app)?;

            // Start socket server in background
            let app_handle = app.handle().clone();
            let state_clone = Arc::clone(&app_state);
            let notification_clone = Arc::clone(&notification_manager);

            tauri::async_runtime::spawn(async move {
                let config = SocketServerConfig::default();
                let server = SocketServer::new(app_handle, state_clone, notification_clone, config);
                if let Err(e) = server.run().await {
                    error!(error = %e, "Socket server failed");
                }
            });

            info!("Application setup completed");

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_tasks,
            commands::remove_task,
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_app_handle, event| {
            if let RunEvent::Exit = event {
                // Cleanup socket file on exit
                let _ = std::fs::remove_file("/tmp/agentpulse.sock");
                info!("Socket file cleaned up");
            }
        });
}
