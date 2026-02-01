# Phase 6: Quality - Detailed Plan

## Overview
Improve stability, logging, and release quality.

## 1. Error handling
- Define `AppError` codes
- Return structured errors to frontend
- Display user-friendly messages

## 2. Logging
- Add tracing and tracing-subscriber
- File + stderr output
- Separate debug and release behavior

## 3. Health checks
- Add a `ping` method for socket health
- Add frontend indicator

## 4. macOS signing and notarization
- Define entitlements
- Add CI signing scripts
- Use notarization pipeline

## 5. Tests
- Error-case tests for socket parsing
- Logging level checks
- Release build verification

## 6. Deliverables
- `src-tauri/src/error.rs`
- `src-tauri/src/logging.rs`
- `src-tauri/entitlements.plist`
- `scripts/sign-and-notarize.sh`
- `scripts/ci-sign.sh`

## Next steps
- User testing
- Performance profiling
- i18n support
- Auto updater
