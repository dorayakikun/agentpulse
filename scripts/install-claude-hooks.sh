#!/bin/bash
# scripts/install-claude-hooks.sh
# Adds Hooks configuration to Claude Code settings.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/claude-code-hook.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Ensure the script is executable
chmod +x "$HOOK_SCRIPT"

# Create settings directory if missing
mkdir -p "$(dirname "$SETTINGS_FILE")"

# New hooks configuration
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

# Merge if settings.json already exists
if [[ -f "$SETTINGS_FILE" ]]; then
    echo "Existing settings found at $SETTINGS_FILE"

    # Check for existing hooks
    EXISTING_HOOKS=$(jq -r '.hooks // empty' "$SETTINGS_FILE")

    if [[ -n "$EXISTING_HOOKS" ]]; then
        echo "WARNING: Existing hooks configuration found!"
        echo "Existing hooks will be preserved and new hooks will be merged."
        echo ""

        # Deep merge: append new hooks to existing hook arrays
        MERGED=$(jq -s '
            def deep_merge:
                reduce .[] as $item ({}; . as $base |
                    $item | to_entries | reduce .[] as $entry ($base;
                        if ($entry.value | type) == "array" and ($base[$entry.key] | type) == "array" then
                            .[$entry.key] = ($base[$entry.key] + $entry.value | unique)
                        elif ($entry.value | type) == "object" and ($base[$entry.key] | type) == "object" then
                            .[$entry.key] = ([$base[$entry.key], $entry.value] | deep_merge)
                        else
                            .[$entry.key] = $entry.value
                        end
                    )
                );
            [.[0], .[1]] | deep_merge
        ' "$SETTINGS_FILE" <(echo "$HOOKS_CONFIG"))
    else
        echo "Merging hooks configuration..."
        # Simple merge when hooks are missing
        MERGED=$(jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$HOOKS_CONFIG"))
    fi

    # Create backup
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
