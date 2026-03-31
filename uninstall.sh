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
for proc in TarsNotch ClawdNotch; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        echo "→ Quitting $proc..."
        killall "$proc" 2>/dev/null || true
        sleep 1
        echo "  ✓ $proc quit"
    fi
done

# --- Step 2: Remove app (current + legacy branding) ---
for app in TarsNotch ClawdNotch; do
    if [ -d "/Applications/$app.app" ]; then
        echo "→ Removing /Applications/$app.app..."
        rm -rf "/Applications/$app.app"
        echo "  ✓ $app.app removed"
    fi
done

# --- Step 3: Remove hooks from both providers ---
remove_hooks() {
    local PROVIDER="$1"
    local CONFIG_DIR="$2"
    local HOOK="$CONFIG_DIR/hooks/tars-status.sh"
    local SETTINGS="$CONFIG_DIR/settings.json"

    echo "→ Removing $PROVIDER hooks..."

    # Remove hook scripts (current + legacy)
    for script in tars-status.sh notchy-status.sh; do
        [ -f "$CONFIG_DIR/hooks/$script" ] && rm -f "$CONFIG_DIR/hooks/$script"
    done
    echo "  ✓ Hook scripts removed"

    # Remove hook entries from settings.json (safe: backup + filter)
    if [ -f "$SETTINGS" ] && grep -qE "tars-status|notchy-status" "$SETTINGS" 2>/dev/null; then
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
            'tars-status' in str(hook.get('command', '')) or 'notchy-status' in str(hook.get('command', ''))
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

# Copilot CLI hooks (current + legacy)
echo "→ Removing Copilot CLI hooks..."
for f in tars-status.sh tars-status-copilot.py tars-status-copilot.sh tars-notch.json notchy-status-copilot.py notchy-status-copilot.sh; do
    rm -f "$HOME/.copilot/hooks/$f"
done
echo "  ✓ Copilot CLI hooks removed"

# --- Step 4: Clean temp files ---
# Clean temp files (current + legacy)
for dir in tars-sessions notchy-sessions; do
    SESS_DIR="${TMPDIR:-/tmp}/$dir"
    [ -d "$SESS_DIR" ] && rm -rf "$SESS_DIR"
done
echo "  ✓ Temp files cleaned"

echo ""
echo "  ✓ Tars Notch fully uninstalled."
echo ""
