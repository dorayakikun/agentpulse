#!/bin/bash
# scripts/install-codex-notify.sh
# Codex の config.toml に notify 設定を追加するスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/codex-notify.sh"
CONFIG_FILE="$HOME/.codex/config.toml"

# スクリプトに実行権限を付与
chmod +x "$NOTIFY_SCRIPT"

# 設定ディレクトリがなければ作成
mkdir -p "$(dirname "$CONFIG_FILE")"

# notify 設定行
NOTIFY_LINE="notify = [\"bash\", \"$NOTIFY_SCRIPT\"]"

# 既存の config.toml がある場合
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Existing config found at $CONFIG_FILE"

    # バックアップを作成
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"

    # notify 設定が既に存在するか確認
    if grep -q "^notify\s*=" "$CONFIG_FILE"; then
        echo "Updating existing notify configuration..."
        # 既存の notify 行を置換
        sed -i.bak "s|^notify\s*=.*|$NOTIFY_LINE|" "$CONFIG_FILE"
        rm -f "${CONFIG_FILE}.bak"
    else
        echo "Adding notify configuration..."
        echo "" >> "$CONFIG_FILE"
        echo "$NOTIFY_LINE" >> "$CONFIG_FILE"
    fi
else
    echo "Creating new config file at $CONFIG_FILE"
    echo "$NOTIFY_LINE" > "$CONFIG_FILE"
fi

echo ""
echo "Codex notify configuration installed successfully!"
echo ""
echo "Notify script location: $NOTIFY_SCRIPT"
echo "Config file: $CONFIG_FILE"
echo ""
echo "To verify, run: cat $CONFIG_FILE"
