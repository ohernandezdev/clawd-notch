#!/bin/bash
set -e

echo ""
echo "  Tars Notch Uninstaller"
echo "  ============================"
echo ""
echo "  This will:"
echo "    1. Quit the app (if running)"
echo "    2. Remove /Applications/TarsNotch.app"
echo "    3. Remove hooks from Claude Code and Copilot CLI"
echo "    4. Clean up temp files"
echo ""
read -rp "  Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Aborted."
    exit 0
fi
echo ""

# --- Step 1: Quit app ---
if pgrep -x "TarsNotch" >/dev/null 2>&1; then
    echo "→ Quitting TarsNotch..."
    killall TarsNotch 2>/dev/null || true
    sleep 1
    echo "  ✓ App quit"
fi

# --- Step 2: Remove app ---
if [ -d "/Applications/TarsNotch.app" ]; then
    echo "→ Removing /Applications/TarsNotch.app..."
    rm -rf "/Applications/TarsNotch.app"
    echo "  ✓ App removed"
else
    echo "→ /Applications/TarsNotch.app not found, skipping"
fi

# --- Step 3: Remove hooks from both providers ---
remove_hooks() {
    local PROVIDER="$1"
    local CONFIG_DIR="$2"
    local HOOK="$CONFIG_DIR/hooks/tars-status.sh"
    local SETTINGS="$CONFIG_DIR/settings.json"

    echo "→ Removing $PROVIDER hooks..."

    # Remove hook script
    if [ -f "$HOOK" ]; then
        rm -f "$HOOK"
        echo "  ✓ Hook script removed"
    fi

    # Remove hook entries from settings.json (safe: backup + filter)
    if [ -f "$SETTINGS" ] && grep -q "tars-status.sh" "$SETTINGS" 2>/dev/null; then
        BACKUP="$SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SETTINGS" "$BACKUP"
        echo "  ✓ Backed up to $BACKUP"

        python3 << PYEOF
import json

with open("$SETTINGS") as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
for event in list(hooks.keys()):
    hooks[event] = [
        h for h in hooks[event]
        if not any(
            'tars-status.sh' in str(hook.get('command', ''))
            for hook in h.get('hooks', [])
        )
    ]
    if not hooks[event]:
        del hooks[event]

if not hooks:
    settings.pop('hooks', None)

with open("$SETTINGS", 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
PYEOF
        echo "  ✓ Hook entries removed from settings.json"
    else
        echo "  ✓ No hook entries found, skipping"
    fi
}

remove_hooks "Claude Code" "$HOME/.claude"

# Copilot CLI uses a separate JSON file, not settings.json
echo "→ Removing Copilot CLI hooks..."
rm -f "$HOME/.copilot/hooks/tars-status.sh"
rm -f "$HOME/.copilot/hooks/tars-notch.json"
echo "  ✓ Copilot CLI hooks removed"

# --- Step 4: Clean temp files ---
TARS_DIR="${TMPDIR:-/tmp}/tars-sessions"
if [ -d "$TARS_DIR" ]; then
    echo "→ Cleaning temp files..."
    rm -rf "$TARS_DIR"
    echo "  ✓ Temp files cleaned"
fi

echo ""
echo "  ✓ Tars Notch fully uninstalled."
echo ""
