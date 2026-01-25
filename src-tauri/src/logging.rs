use std::path::PathBuf;
use tracing::Level;
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{
    fmt::{self, format::FmtSpan},
    layer::SubscriberExt,
    util::SubscriberInitExt,
    EnvFilter,
};

/// ログ設定
pub struct LogConfig {
    pub level: Level,
    pub log_dir: Option<PathBuf>,
    pub json_format: bool,
}

impl Default for LogConfig {
    fn default() -> Self {
        Self {
            level: Level::INFO,
            log_dir: None,
            json_format: false,
        }
    }
}

/// ロギングを初期化（戻り値のガードはドロップしないこと）
pub fn init_logging(config: LogConfig) -> Option<WorkerGuard> {
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        EnvFilter::new(format!(
            "ai_agent_status={},ai_agent_status_lib={},tauri=warn",
            config.level.as_str().to_lowercase(),
            config.level.as_str().to_lowercase()
        ))
    });

    // ファイル出力が設定されている場合
    if let Some(log_dir) = config.log_dir {
        // ログディレクトリを作成
        if let Err(e) = std::fs::create_dir_all(&log_dir) {
            eprintln!(
                "Failed to create log directory {:?}: {}. Falling back to stderr-only logging.",
                log_dir, e
            );
            // stderr のみにフォールバック
            tracing_subscriber::registry()
                .with(env_filter)
                .with(
                    fmt::layer()
                        .compact()
                        .with_target(true)
                        .with_writer(std::io::stderr),
                )
                .init();
            return None;
        }

        let file_appender = tracing_appender::rolling::daily(&log_dir, "ai-agent-status.log");
        let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);

        if config.json_format {
            tracing_subscriber::registry()
                .with(env_filter)
                .with(
                    fmt::layer()
                        .json()
                        .with_writer(non_blocking)
                        .with_span_events(FmtSpan::CLOSE),
                )
                .with(
                    fmt::layer()
                        .compact()
                        .with_target(false)
                        .with_writer(std::io::stderr),
                )
                .init();
        } else {
            tracing_subscriber::registry()
                .with(env_filter)
                .with(
                    fmt::layer()
                        .with_writer(non_blocking)
                        .with_span_events(FmtSpan::CLOSE),
                )
                .with(
                    fmt::layer()
                        .compact()
                        .with_target(false)
                        .with_writer(std::io::stderr),
                )
                .init();
        }

        Some(guard)
    } else {
        // stderr のみ
        tracing_subscriber::registry()
            .with(env_filter)
            .with(
                fmt::layer()
                    .compact()
                    .with_target(true)
                    .with_writer(std::io::stderr),
            )
            .init();

        None
    }
}

/// ログディレクトリのパスを取得
pub fn get_log_dir() -> Option<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        dirs::home_dir().map(|h| h.join("Library/Logs/AI Agent Status"))
    }

    #[cfg(target_os = "linux")]
    {
        dirs::data_local_dir().map(|d| d.join("ai-agent-status/logs"))
    }

    #[cfg(target_os = "windows")]
    {
        dirs::data_local_dir().map(|d| d.join("AI Agent Status\\logs"))
    }
}
