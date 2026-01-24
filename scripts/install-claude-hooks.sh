#!/bin/bash
# scripts/install-claude-hooks.sh
# Claude Code の settings.json に Hooks 設定を追加するスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/claude-code-hook.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

# スクリプトに実行権限を付与
chmod +x "$HOOK_SCRIPT"

# 設定ディレクトリがなければ作成
mkdir -p "$(dirname "$SETTINGS_FILE")"

# 新しい hooks 設定
HOOKS_CONFIG=$(cat <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT session_start" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT pre_tool" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT post_tool" }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT notification" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "$HOOK_SCRIPT session_end" }
        ]
      }
    ]
  }
}
EOF
)

# 既存の settings.json がある場合はマージ
if [[ -f "$SETTINGS_FILE" ]]; then
    echo "Existing settings found at $SETTINGS_FILE"
    echo "Merging hooks configuration..."

    # 既存の設定と新しい hooks をマージ
    MERGED=$(jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$HOOKS_CONFIG"))

    # バックアップを作成
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup.$(date +%Y%m%d%H%M%S)"

    echo "$MERGED" > "$SETTINGS_FILE"
else
    echo "Creating new settings file at $SETTINGS_FILE"
    echo "$HOOKS_CONFIG" > "$SETTINGS_FILE"
fi

echo ""
echo "Claude Code Hooks configuration installed successfully!"
echo ""
echo "Hook script location: $HOOK_SCRIPT"
echo "Settings file: $SETTINGS_FILE"
echo ""
echo "To verify, run: cat $SETTINGS_FILE | jq '.hooks'"
