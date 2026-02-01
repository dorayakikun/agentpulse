#!/bin/bash
# Script to sign and notarize the macOS app
# Usage: ./scripts/sign-and-notarize.sh

set -euo pipefail

# Config
APP_NAME="AgentPulse"
BUNDLE_ID="com.agentpulse.app"
APP_PATH="./src-tauri/target/release/bundle/macos/${APP_NAME}.app"
DMG_PATH="./src-tauri/target/release/bundle/dmg/${APP_NAME}.dmg"

# Environment checks
: "${APPLE_ID:?APPLE_ID environment variable is required}"
: "${APPLE_ID_PASSWORD:?APPLE_ID_PASSWORD environment variable is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID environment variable is required}"

# Find signing certificate
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Error: Developer ID Application certificate not found"
    exit 1
fi
echo "Using signing identity: $SIGNING_IDENTITY"

# Build
echo "Building release..."
npm run tauri build

# Code signing
echo "Signing application..."
codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
    --entitlements ./src-tauri/entitlements.plist \
    --deep "$APP_PATH"

# Verify signature
echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

# Sign DMG
if [[ -f "$DMG_PATH" ]]; then
    echo "Signing DMG..."
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi

# Notarize
if [[ -f "$DMG_PATH" ]]; then
    echo "Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --primary-bundle-id "$BUNDLE_ID" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

    # Staple notarization ticket
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"

    # Final verification
    echo "Final verification..."
    spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
else
    echo "WARNING: DMG file not found at $DMG_PATH"
    echo "Skipping notarization step."
fi

echo ""
echo "Signing and notarization completed successfully!"
echo "DMG: $DMG_PATH"
