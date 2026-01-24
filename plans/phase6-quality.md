# Phase 6: 品質向上 - 詳細計画

## 概要

アプリケーションの品質を向上させ、本番環境での運用に耐えうる堅牢性を実現する。エラーハンドリング、ロギング、macOS 署名・公証の3つの柱で構成。

---

## 前提条件

### 6.1 Phase 1-5 が完了していること

```bash
# アプリがビルド・動作することを確認
npm run tauri dev
```

### 6.2 macOS 署名に必要なもの

| 項目 | 説明 |
|------|------|
| Apple Developer Program | 年間 $99 |
| Developer ID Application 証明書 | コード署名用 |
| Developer ID Installer 証明書 | パッケージ署名用 |
| App-specific password | 公証 API 用 |

---

## 1. エラーハンドリング

### 1.1 Rust エラー型の定義

#### src-tauri/src/error.rs (新規)

```rust
use thiserror::Error;

/// アプリケーションエラー型
#[derive(Debug, Error)]
pub enum AppError {
    #[error("Socket error: {0}")]
    Socket(#[from] std::io::Error),

    #[error("JSON parse error: {0}")]
    JsonParse(#[from] serde_json::Error),

    #[error("Task not found: {session_id}")]
    TaskNotFound { session_id: String },

    #[error("Invalid event: {message}")]
    InvalidEvent { message: String },

    #[error("Notification failed: {0}")]
    Notification(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

/// Tauri コマンド用の Result 型
pub type AppResult<T> = Result<T, AppError>;

/// Tauri コマンドからの JSON レスポンス用
impl serde::Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut state = serializer.serialize_struct("AppError", 2)?;
        state.serialize_field("code", &self.error_code())?;
        state.serialize_field("message", &self.to_string())?;
        state.end()
    }
}

impl AppError {
    /// エラーコード（Frontend でのハンドリング用）
    pub fn error_code(&self) -> &'static str {
        match self {
            AppError::Socket(_) => "SOCKET_ERROR",
            AppError::JsonParse(_) => "JSON_PARSE_ERROR",
            AppError::TaskNotFound { .. } => "TASK_NOT_FOUND",
            AppError::InvalidEvent { .. } => "INVALID_EVENT",
            AppError::Notification(_) => "NOTIFICATION_ERROR",
            AppError::Internal(_) => "INTERNAL_ERROR",
        }
    }

    /// リカバリ可能かどうか
    pub fn is_recoverable(&self) -> bool {
        match self {
            AppError::Socket(_) => true,
            AppError::JsonParse(_) => true,
            AppError::TaskNotFound { .. } => true,
            AppError::InvalidEvent { .. } => true,
            AppError::Notification(_) => false,
            AppError::Internal(_) => false,
        }
    }
}
```

### 1.2 ソケットサーバーのエラーハンドリング強化

#### src-tauri/src/socket_server.rs の改善

```rust
use crate::error::{AppError, AppResult};
use log::{debug, error, info, warn};
use std::time::Duration;
use tokio::net::UnixListener;
use tokio::time::timeout;

const READ_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_MESSAGE_SIZE: usize = 1024 * 1024; // 1MB

impl SocketServer {
    /// 安全なメッセージ読み取り
    async fn read_message_safe(&self, stream: &mut UnixStream) -> AppResult<String> {
        let mut buffer = vec![0u8; 4096];
        let mut message = String::new();

        loop {
            match timeout(READ_TIMEOUT, stream.read(&mut buffer)).await {
                Ok(Ok(0)) => break, // EOF
                Ok(Ok(n)) => {
                    if message.len() + n > MAX_MESSAGE_SIZE {
                        return Err(AppError::InvalidEvent {
                            message: "Message too large".to_string(),
                        });
                    }
                    message.push_str(&String::from_utf8_lossy(&buffer[..n]));
                    if message.contains('\n') {
                        break;
                    }
                }
                Ok(Err(e)) => {
                    warn!("Read error: {}", e);
                    return Err(AppError::Socket(e));
                }
                Err(_) => {
                    warn!("Read timeout");
                    return Err(AppError::Socket(std::io::Error::new(
                        std::io::ErrorKind::TimedOut,
                        "Read timeout",
                    )));
                }
            }
        }

        Ok(message)
    }

    /// メッセージの検証とパース
    fn parse_message(&self, raw: &str) -> AppResult<JsonRpcRequest> {
        // 空メッセージのチェック
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return Err(AppError::InvalidEvent {
                message: "Empty message".to_string(),
            });
        }

        // JSON パース
        serde_json::from_str(trimmed).map_err(|e| {
            debug!("Invalid JSON: {}", trimmed);
            AppError::JsonParse(e)
        })
    }

    /// 接続ハンドラ（エラーリカバリ付き）
    async fn handle_connection(&self, mut stream: UnixStream) {
        let peer_addr = stream
            .peer_addr()
            .map(|a| format!("{:?}", a))
            .unwrap_or_else(|_| "unknown".to_string());

        debug!("New connection from: {}", peer_addr);

        loop {
            match self.read_message_safe(&mut stream).await {
                Ok(message) => {
                    for line in message.lines() {
                        match self.parse_message(line) {
                            Ok(request) => {
                                if let Err(e) = self.handle_request(request).await {
                                    warn!("Request handling failed: {}", e);
                                }
                            }
                            Err(e) if e.is_recoverable() => {
                                debug!("Recoverable error: {}", e);
                                continue;
                            }
                            Err(e) => {
                                error!("Non-recoverable error: {}", e);
                                return;
                            }
                        }
                    }
                }
                Err(e) if e.is_recoverable() => {
                    debug!("Connection error (recoverable): {}", e);
                    continue;
                }
                Err(e) => {
                    debug!("Connection closed: {}", e);
                    break;
                }
            }
        }

        debug!("Connection closed: {}", peer_addr);
    }
}
```

### 1.3 Tauri コマンドのエラーハンドリング

#### src-tauri/src/commands.rs の改善

```rust
use crate::error::{AppError, AppResult};
use crate::models::Task;
use crate::state::AppState;
use tauri::State;

/// 全タスクを取得
#[tauri::command]
pub fn get_tasks(state: State<AppState>) -> AppResult<Vec<Task>> {
    Ok(state.get_all_tasks())
}

/// タスクを削除
#[tauri::command]
pub fn remove_task(session_id: String, state: State<AppState>) -> AppResult<Task> {
    state
        .remove_task(&session_id)
        .ok_or_else(|| AppError::TaskNotFound {
            session_id: session_id.clone(),
        })
}

/// タスク詳細を取得
#[tauri::command]
pub fn get_task(session_id: String, state: State<AppState>) -> AppResult<Task> {
    state
        .get_task(&session_id)
        .ok_or_else(|| AppError::TaskNotFound { session_id })
}
```

### 1.4 Frontend エラーハンドリング

#### src/types/error.ts (新規)

```typescript
// Backend からのエラーレスポンス
export interface AppError {
  code: string;
  message: string;
}

// エラーコード定義
export const ErrorCodes = {
  SOCKET_ERROR: 'SOCKET_ERROR',
  JSON_PARSE_ERROR: 'JSON_PARSE_ERROR',
  TASK_NOT_FOUND: 'TASK_NOT_FOUND',
  INVALID_EVENT: 'INVALID_EVENT',
  NOTIFICATION_ERROR: 'NOTIFICATION_ERROR',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
} as const;

export type ErrorCode = typeof ErrorCodes[keyof typeof ErrorCodes];

// ユーザー向けメッセージ
export const ErrorMessages: Record<ErrorCode, string> = {
  SOCKET_ERROR: 'Connection error. The monitoring service may be unavailable.',
  JSON_PARSE_ERROR: 'Failed to process data from agent.',
  TASK_NOT_FOUND: 'Task not found. It may have already completed.',
  INVALID_EVENT: 'Received invalid data from agent.',
  NOTIFICATION_ERROR: 'Failed to send notification.',
  INTERNAL_ERROR: 'An unexpected error occurred.',
};

// エラーからユーザーメッセージを取得
export function getUserMessage(error: AppError | Error | unknown): string {
  if (error && typeof error === 'object' && 'code' in error) {
    const appError = error as AppError;
    return ErrorMessages[appError.code as ErrorCode] || appError.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return 'An unexpected error occurred.';
}
```

#### src/hooks/useTasks.ts の改善

```typescript
import { useState, useEffect, useCallback, useRef } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen, UnlistenFn } from '@tauri-apps/api/event';
import { Task, TasksUpdatedPayload } from '../types/task';
import { getUserMessage } from '../types/error';

const MAX_RETRIES = 3;
const RETRY_DELAY = 1000;

export function useTasks() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const retryCount = useRef(0);

  const fetchTasks = useCallback(async (isRetry = false) => {
    try {
      if (!isRetry) {
        setIsLoading(true);
        setError(null);
      }

      const result = await invoke<Task[]>('get_tasks');
      setTasks(result);
      retryCount.current = 0; // リセット
    } catch (err) {
      const message = getUserMessage(err);

      if (retryCount.current < MAX_RETRIES) {
        retryCount.current++;
        console.warn(`Fetch failed, retrying (${retryCount.current}/${MAX_RETRIES})...`);
        setTimeout(() => fetchTasks(true), RETRY_DELAY * retryCount.current);
        return;
      }

      setError(message);
      console.error('Failed to fetch tasks:', err);
    } finally {
      if (!isRetry || retryCount.current >= MAX_RETRIES) {
        setIsLoading(false);
      }
    }
  }, []);

  useEffect(() => {
    fetchTasks();

    let unlisten: UnlistenFn | null = null;
    const setupListener = async () => {
      try {
        unlisten = await listen<TasksUpdatedPayload>('tasks-updated', (event) => {
          setTasks(event.payload.tasks);
          setError(null); // エラークリア
        });
      } catch (err) {
        console.error('Failed to setup event listener:', err);
      }
    };
    setupListener();

    return () => {
      unlisten?.();
    };
  }, [fetchTasks]);

  const clearError = useCallback(() => setError(null), []);

  return { tasks, isLoading, error, refresh: fetchTasks, clearError };
}
```

#### src/components/ErrorBanner.tsx (新規)

```typescript
import { FC } from 'react';

interface ErrorBannerProps {
  message: string;
  onDismiss?: () => void;
  onRetry?: () => void;
}

export const ErrorBanner: FC<ErrorBannerProps> = ({ message, onDismiss, onRetry }) => {
  return (
    <div className="error-banner" role="alert">
      <div className="error-banner-content">
        <span className="error-icon">⚠️</span>
        <p className="error-message">{message}</p>
      </div>
      <div className="error-banner-actions">
        {onRetry && (
          <button className="error-action" onClick={onRetry}>
            Retry
          </button>
        )}
        {onDismiss && (
          <button className="error-dismiss" onClick={onDismiss} aria-label="Dismiss">
            ×
          </button>
        )}
      </div>
    </div>
  );
};
```

---

## 2. ロギング

### 2.1 構造化ロギング設定

#### src-tauri/Cargo.toml への追加

```toml
[dependencies]
# 既存の log, env_logger に加えて
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["json", "env-filter"] }
tracing-appender = "0.2"
```

### 2.2 ロギングモジュール

#### src-tauri/src/logging.rs (新規)

```rust
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
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| {
            EnvFilter::new(format!(
                "ai_agent_status={},tauri=warn",
                config.level.as_str().to_lowercase()
            ))
        });

    // ファイル出力が設定されている場合
    if let Some(log_dir) = config.log_dir {
        let file_appender = tracing_appender::rolling::daily(log_dir, "ai-agent-status.log");
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
```

### 2.3 アプリケーション内でのロギング使用

#### src-tauri/src/main.rs の改善

```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod error;
mod logging;
mod models;
mod socket_server;
mod state;
mod tray;

use logging::{get_log_dir, init_logging, LogConfig};
use state::AppState;
use tauri::Manager;
use tracing::{error, info, warn, Level};

#[cfg(target_os = "macos")]
use tauri::ActivationPolicy;

fn main() {
    // ロギング初期化
    let log_config = LogConfig {
        level: if cfg!(debug_assertions) {
            Level::DEBUG
        } else {
            Level::INFO
        },
        log_dir: get_log_dir(),
        json_format: !cfg!(debug_assertions),
    };

    // ガードを保持（ドロップするとログが失われる）
    let _guard = init_logging(log_config);

    info!(version = env!("CARGO_PKG_VERSION"), "Starting AI Agent Status Monitor");

    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_shell::init())
        .manage(AppState::new())
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(ActivationPolicy::Accessory)?;

            tray::setup_tray(app)?;

            // ソケットサーバー起動
            let app_handle = app.handle().clone();
            let state = app.state::<AppState>().inner().clone();

            tauri::async_runtime::spawn(async move {
                if let Err(e) = socket_server::start_server(app_handle, state).await {
                    error!(error = %e, "Socket server failed");
                }
            });

            info!("Application setup completed");
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_tasks,
            commands::remove_task,
            commands::get_task,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### 2.4 ソケットサーバーのロギング追加

```rust
use tracing::{debug, error, info, instrument, span, warn, Level};

impl SocketServer {
    #[instrument(skip(self, stream), fields(peer = %peer_addr))]
    async fn handle_connection(&self, mut stream: UnixStream, peer_addr: String) {
        info!("Client connected");

        // ... 処理 ...

        info!("Client disconnected");
    }

    #[instrument(skip(self), fields(method = %request.method))]
    async fn handle_request(&self, request: JsonRpcRequest) -> AppResult<()> {
        debug!(params = ?request.params, "Processing request");

        // ... 処理 ...

        Ok(())
    }
}
```

### 2.5 ログローテーション設定

```rust
// tracing_appender::rolling の設定オプション
// daily: 日次ローテーション
// hourly: 時間ごと
// minutely: 分ごと（デバッグ用）
// never: ローテーションなし

let file_appender = tracing_appender::rolling::RollingFileAppender::builder()
    .rotation(tracing_appender::rolling::Rotation::DAILY)
    .filename_prefix("ai-agent-status")
    .filename_suffix("log")
    .max_log_files(7) // 7日分保持
    .build(log_dir)
    .expect("Failed to create log appender");
```

---

## 3. macOS 署名・公証

### 3.1 事前準備

#### 証明書の取得

1. Apple Developer Program に登録
2. Keychain Access で CSR (Certificate Signing Request) を作成
3. Apple Developer サイトで証明書を発行:
   - Developer ID Application (コード署名用)
   - Developer ID Installer (パッケージ署名用)
4. 証明書をダウンロードし、Keychain にインストール

#### App-specific password の作成

1. appleid.apple.com にログイン
2. "App-specific passwords" から新規作成
3. 環境変数に設定:

```bash
export APPLE_ID="your@email.com"
export APPLE_ID_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="XXXXXXXXXX"
```

### 3.2 tauri.conf.json の署名設定

```json
{
  "bundle": {
    "active": true,
    "targets": ["dmg", "app"],
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns"
    ],
    "macOS": {
      "minimumSystemVersion": "10.15",
      "entitlements": "./entitlements.plist",
      "signingIdentity": "-",
      "providerShortName": null,
      "hardenedRuntime": true
    }
  }
}
```

### 3.3 Entitlements ファイル

#### src-tauri/entitlements.plist (新規)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ネットワーク（クライアント接続用） -->
    <key>com.apple.security.network.client</key>
    <true/>

    <!-- Unix ソケット通信用 -->
    <key>com.apple.security.network.server</key>
    <true/>

    <!-- Hardened Runtime でも動的ライブラリをロード可能に -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>

    <!-- JIT コンパイル（通常不要） -->
    <key>com.apple.security.cs.allow-jit</key>
    <false/>

    <!-- デバッガアタッチを許可（開発用、リリースでは false） -->
    <key>com.apple.security.cs.debugger</key>
    <false/>
</dict>
</plist>
```

### 3.4 署名・公証スクリプト

#### scripts/sign-and-notarize.sh (新規)

```bash
#!/bin/bash
# macOS アプリの署名と公証を行うスクリプト
# Usage: ./scripts/sign-and-notarize.sh

set -euo pipefail

# 設定
APP_NAME="AI Agent Status"
BUNDLE_ID="com.ai-agent-status.app"
APP_PATH="./src-tauri/target/release/bundle/macos/${APP_NAME}.app"
DMG_PATH="./src-tauri/target/release/bundle/dmg/${APP_NAME}.dmg"

# 環境変数チェック
: "${APPLE_ID:?APPLE_ID environment variable is required}"
: "${APPLE_ID_PASSWORD:?APPLE_ID_PASSWORD environment variable is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID environment variable is required}"

# 署名証明書の検索
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Error: Developer ID Application certificate not found"
    exit 1
fi
echo "Using signing identity: $SIGNING_IDENTITY"

# ビルド
echo "Building release..."
npm run tauri build

# コード署名
echo "Signing application..."
codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
    --entitlements ./src-tauri/entitlements.plist \
    --deep "$APP_PATH"

# 署名検証
echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

# DMG の署名
if [[ -f "$DMG_PATH" ]]; then
    echo "Signing DMG..."
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi

# 公証
echo "Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_ID_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

# Staple（公証チケットを添付）
echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# 最終検証
echo "Final verification..."
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"

echo ""
echo "✅ Signing and notarization completed successfully!"
echo "DMG: $DMG_PATH"
```

### 3.5 CI/CD 用スクリプト

#### scripts/ci-sign.sh (新規)

```bash
#!/bin/bash
# CI/CD 環境での署名スクリプト
# 証明書は Base64 エンコードで環境変数から読み込む

set -euo pipefail

# 環境変数から証明書をインポート
: "${APPLE_CERTIFICATE_BASE64:?Certificate not set}"
: "${APPLE_CERTIFICATE_PASSWORD:?Certificate password not set}"

# 一時キーチェーンを作成
KEYCHAIN_PATH="$HOME/Library/Keychains/build.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -base64 32)

security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
security default-keychain -s build.keychain
security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
security set-keychain-settings -t 3600 -u build.keychain

# 証明書をインポート
echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > certificate.p12
security import certificate.p12 -k build.keychain -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
rm certificate.p12

# キーチェーンをコード署名に使用可能にする
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" build.keychain

echo "Certificate imported successfully"

# 署名実行（sign-and-notarize.sh を呼び出し）
./scripts/sign-and-notarize.sh

# クリーンアップ
security delete-keychain build.keychain
```

### 3.6 GitHub Actions ワークフロー

#### .github/workflows/release.yml (新規)

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Setup Rust
        uses: dtolnay/rust-action@stable

      - name: Install dependencies
        run: npm ci

      - name: Import certificate
        env:
          APPLE_CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: ./scripts/ci-sign.sh import-cert

      - name: Build and sign
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_ID_PASSWORD: ${{ secrets.APPLE_ID_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: ./scripts/sign-and-notarize.sh

      - name: Upload DMG
        uses: actions/upload-artifact@v4
        with:
          name: AI-Agent-Status-macOS
          path: ./src-tauri/target/release/bundle/dmg/*.dmg

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: ./src-tauri/target/release/bundle/dmg/*.dmg
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## 4. 追加の品質向上項目

### 4.1 ヘルスチェック機能

#### src-tauri/src/health.rs (新規)

```rust
use serde::Serialize;
use std::time::{Duration, Instant};

#[derive(Debug, Serialize)]
pub struct HealthStatus {
    pub status: &'static str,
    pub uptime_seconds: u64,
    pub socket_server_running: bool,
    pub active_tasks: usize,
    pub last_event_received: Option<u64>,
}

pub struct HealthChecker {
    start_time: Instant,
    last_event: std::sync::Mutex<Option<Instant>>,
}

impl HealthChecker {
    pub fn new() -> Self {
        Self {
            start_time: Instant::now(),
            last_event: std::sync::Mutex::new(None),
        }
    }

    pub fn record_event(&self) {
        *self.last_event.lock().unwrap() = Some(Instant::now());
    }

    pub fn get_status(&self, socket_running: bool, task_count: usize) -> HealthStatus {
        let last_event_secs = self
            .last_event
            .lock()
            .unwrap()
            .map(|t| t.elapsed().as_secs());

        HealthStatus {
            status: if socket_running { "healthy" } else { "degraded" },
            uptime_seconds: self.start_time.elapsed().as_secs(),
            socket_server_running: socket_running,
            active_tasks: task_count,
            last_event_received: last_event_secs,
        }
    }
}
```

### 4.2 パニックハンドラ

#### src-tauri/src/main.rs への追加

```rust
fn setup_panic_handler() {
    std::panic::set_hook(Box::new(|panic_info| {
        let location = panic_info.location().map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column())).unwrap_or_default();
        let message = panic_info.payload().downcast_ref::<&str>().unwrap_or(&"Unknown panic");

        error!(
            location = %location,
            message = %message,
            "Application panicked"
        );

        // クラッシュレポートをファイルに出力
        if let Some(log_dir) = get_log_dir() {
            let crash_file = log_dir.join(format!(
                "crash-{}.txt",
                chrono::Utc::now().format("%Y%m%d-%H%M%S")
            ));
            let _ = std::fs::write(
                &crash_file,
                format!("Panic at {}\n{}", location, message),
            );
        }
    }));
}
```

---

## 5. 実装順序

### チェックリスト

```
□ 1. エラーハンドリング
  □ error.rs (AppError 型定義)
  □ socket_server.rs の改善
  □ commands.rs の改善
  □ Frontend error.ts
  □ ErrorBanner コンポーネント
  □ useTasks フックの改善

□ 2. ロギング
  □ Cargo.toml に tracing 追加
  □ logging.rs (初期化)
  □ main.rs にロギング統合
  □ socket_server.rs に計装追加
  □ ログローテーション設定

□ 3. ヘルスチェック
  □ health.rs
  □ Tauri コマンド追加
  □ Frontend ステータス表示

□ 4. macOS 署名・公証
  □ entitlements.plist
  □ tauri.conf.json 署名設定
  □ sign-and-notarize.sh
  □ ci-sign.sh
  □ GitHub Actions ワークフロー

□ 5. テスト・検証
  □ エラーケーステスト
  □ ログ出力確認
  □ 署名・公証テスト
  □ 配布テスト
```

---

## 6. テスト

### 6.1 エラーハンドリングテスト

| テストケース | 入力 | 期待結果 |
|------------|------|----------|
| 不正な JSON | `{invalid}` | JsonParse エラー、ログ出力、接続継続 |
| 巨大メッセージ | 1MB 超 | InvalidEvent エラー、接続クローズ |
| タイムアウト | 30秒無応答 | Socket エラー、接続クローズ |
| 存在しないタスク | 無効な session_id | TaskNotFound エラー、UI にメッセージ表示 |

### 6.2 ロギングテスト

```bash
# ログレベル設定
RUST_LOG=debug npm run tauri dev

# ログファイル確認 (macOS)
tail -f ~/Library/Logs/AI\ Agent\ Status/ai-agent-status.*.log

# JSON フォーマット確認 (リリースビルド)
npm run tauri build
./src-tauri/target/release/ai-agent-status
cat ~/Library/Logs/AI\ Agent\ Status/ai-agent-status.*.log | jq .
```

### 6.3 署名・公証テスト

```bash
# 署名検証
codesign -dv --verbose=4 "./src-tauri/target/release/bundle/macos/AI Agent Status.app"

# Gatekeeper 検証
spctl --assess --type execute -v "./src-tauri/target/release/bundle/macos/AI Agent Status.app"

# 公証ログ確認
xcrun notarytool log <submission-id> --apple-id "$APPLE_ID" --password "$APPLE_ID_PASSWORD" --team-id "$APPLE_TEAM_ID"
```

---

## Critical Files

| ファイル | 役割 |
|----------|------|
| `src-tauri/src/error.rs` | エラー型定義 |
| `src-tauri/src/logging.rs` | ロギング設定 |
| `src-tauri/entitlements.plist` | macOS エンタイトルメント |
| `scripts/sign-and-notarize.sh` | 署名・公証スクリプト |
| `.github/workflows/release.yml` | リリース自動化 |
| `src/types/error.ts` | Frontend エラー型 |
| `src/components/ErrorBanner.tsx` | エラー表示 UI |

---

## 次のステップ

Phase 6 完了後:

1. **ユーザーテスト**: 実際のユーザーによるフィードバック収集
2. **パフォーマンス最適化**: プロファイリングに基づく最適化
3. **多言語対応**: i18n の実装
4. **自動更新**: tauri-plugin-updater の導入
