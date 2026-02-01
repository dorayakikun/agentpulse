#!/bin/bash
# Signing script for CI/CD
# Certificates are loaded from Base64-encoded env vars
#
# Usage:
#   ./scripts/ci-sign.sh import-cert  # import certificate only
#   ./scripts/ci-sign.sh notarize     # sign + notarize
#   ./scripts/ci-sign.sh cleanup      # delete keychain
#   ./scripts/ci-sign.sh              # run all steps (import-cert + notarize + cleanup)

set -euo pipefail

KEYCHAIN_NAME="build.keychain"
KEYCHAIN_PATH="$HOME/Library/Keychains/${KEYCHAIN_NAME}-db"
KEYCHAIN_PASSWORD_FILE="/tmp/.keychain_password"

import_cert() {
    # Import certificate from environment variables
    : "${APPLE_CERTIFICATE_BASE64:?Certificate not set}"
    : "${APPLE_CERTIFICATE_PASSWORD:?Certificate password not set}"

    # Generate and store keychain password (used by later steps)
    KEYCHAIN_PASSWORD=$(openssl rand -base64 32)
    echo "$KEYCHAIN_PASSWORD" > "$KEYCHAIN_PASSWORD_FILE"
    chmod 600 "$KEYCHAIN_PASSWORD_FILE"

    # Create temporary keychain
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
    security default-keychain -s "$KEYCHAIN_NAME"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
    security set-keychain-settings -t 3600 -u "$KEYCHAIN_NAME"

    # Import certificate
    echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > certificate.p12
    security import certificate.p12 -k "$KEYCHAIN_NAME" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
    rm certificate.p12

    # Allow keychain to be used for code signing
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"

    echo "Certificate imported successfully"
}

notarize() {
    # Run signing (call sign-and-notarize.sh)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    "$SCRIPT_DIR/sign-and-notarize.sh"
}

cleanup() {
    # Delete keychain
    if security list-keychains | grep -q "$KEYCHAIN_NAME"; then
        security delete-keychain "$KEYCHAIN_NAME"
        echo "Keychain deleted"
    fi
    # Delete password file
    rm -f "$KEYCHAIN_PASSWORD_FILE"
}

# Subcommand handling
case "${1:-all}" in
    import-cert)
        import_cert
        ;;
    notarize)
        notarize
        ;;
    cleanup)
        cleanup
        ;;
    all)
        import_cert
        notarize
        cleanup
        ;;
    *)
        echo "Usage: $0 {import-cert|notarize|cleanup|all}"
        exit 1
        ;;
esac
