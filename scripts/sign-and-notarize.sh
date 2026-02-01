#!/bin/bash
# macOS アプリの署名と公証を行うスクリプト
# Usage: ./scripts/sign-and-notarize.sh

set -euo pipefail

# 設定
APP_NAME="AgentPulse"
BUNDLE_ID="com.agentpulse.app"
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
if [[ -f "$DMG_PATH" ]]; then
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
else
    echo "WARNING: DMG file not found at $DMG_PATH"
    echo "Skipping notarization step."
fi

echo ""
echo "Signing and notarization completed successfully!"
echo "DMG: $DMG_PATH"
