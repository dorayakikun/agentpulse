#!/bin/bash
# scripts/install-codex-notify.sh
# Adds notify configuration to Codex config.toml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY_SCRIPT="$SCRIPT_DIR/codex-notify.sh"
CONFIG_FILE="$HOME/.codex/config.toml"

# Ensure the script is executable
chmod +x "$NOTIFY_SCRIPT"

# Create config directory if missing
mkdir -p "$(dirname "$CONFIG_FILE")"

# notify config line
NOTIFY_LINE="notify = [\"bash\", \"$NOTIFY_SCRIPT\"]"

# If config.toml already exists
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Existing config found at $CONFIG_FILE"

    # Create backup
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"

    # Check if notify config already exists (POSIX-compatible regex)
    if grep -q "^[[:space:]]*notify[[:space:]]*=" "$CONFIG_FILE"; then
        echo "Updating existing notify configuration..."
        # Replace existing notify line (preserve indentation)
        sed -i.bak "s|^\([[:space:]]*\)notify[[:space:]]*=.*|\1$NOTIFY_LINE|" "$CONFIG_FILE"
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
