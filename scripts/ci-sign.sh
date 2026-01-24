#!/bin/bash
# CI/CD 環境での署名スクリプト
# 証明書は Base64 エンコードで環境変数から読み込む
#
# 使用方法:
#   ./scripts/ci-sign.sh import-cert  # 証明書インポートのみ
#   ./scripts/ci-sign.sh notarize     # 署名・公証を実行
#   ./scripts/ci-sign.sh cleanup      # キーチェーンを削除
#   ./scripts/ci-sign.sh              # 全ステップを実行（import-cert + notarize + cleanup）

set -euo pipefail

KEYCHAIN_NAME="build.keychain"
KEYCHAIN_PATH="$HOME/Library/Keychains/${KEYCHAIN_NAME}-db"
KEYCHAIN_PASSWORD_FILE="/tmp/.keychain_password"

import_cert() {
    # 環境変数から証明書をインポート
    : "${APPLE_CERTIFICATE_BASE64:?Certificate not set}"
    : "${APPLE_CERTIFICATE_PASSWORD:?Certificate password not set}"

    # キーチェーンパスワードを生成して保存（後続ステップで使用）
    KEYCHAIN_PASSWORD=$(openssl rand -base64 32)
    echo "$KEYCHAIN_PASSWORD" > "$KEYCHAIN_PASSWORD_FILE"
    chmod 600 "$KEYCHAIN_PASSWORD_FILE"

    # 一時キーチェーンを作成
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
    security default-keychain -s "$KEYCHAIN_NAME"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
    security set-keychain-settings -t 3600 -u "$KEYCHAIN_NAME"

    # 証明書をインポート
    echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > certificate.p12
    security import certificate.p12 -k "$KEYCHAIN_NAME" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
    rm certificate.p12

    # キーチェーンをコード署名に使用可能にする
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"

    echo "Certificate imported successfully"
}

notarize() {
    # 署名実行（sign-and-notarize.sh を呼び出し）
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    "$SCRIPT_DIR/sign-and-notarize.sh"
}

cleanup() {
    # キーチェーンを削除
    if security list-keychains | grep -q "$KEYCHAIN_NAME"; then
        security delete-keychain "$KEYCHAIN_NAME"
        echo "Keychain deleted"
    fi
    # パスワードファイルを削除
    rm -f "$KEYCHAIN_PASSWORD_FILE"
}

# サブコマンド処理
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
