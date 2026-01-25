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

    # 既存の hooks があるかチェック
    EXISTING_HOOKS=$(jq -r '.hooks // empty' "$SETTINGS_FILE")

    if [[ -n "$EXISTING_HOOKS" ]]; then
        echo "WARNING: Existing hooks configuration found!"
        echo "Existing hooks will be preserved and new hooks will be merged."
        echo ""

        # ディープマージ: 既存の hooks 配列に新しい hooks を追加
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
        # hooks がない場合は単純マージ
        MERGED=$(jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$HOOKS_CONFIG"))
    fi

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
