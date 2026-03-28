#!/bin/bash
set -e

echo ""
echo "  🦀 Claw'd Notch Uninstaller"
echo "  ============================"
echo ""
echo "  This will:"
echo "    1. Quit the app (if running)"
echo "    2. Remove /Applications/ClawdNotch.app"
echo "    3. Remove ~/.claude/hooks/notchy-status.sh"
echo "    4. Remove hook entries from ~/.claude/settings.json"
echo "    5. Clean up temp files"
echo ""
read -rp "  Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Aborted."
    exit 0
fi
echo ""

# --- Step 1: Quit app ---
if pgrep -x "ClawdNotch" >/dev/null 2>&1; then
    echo "→ Quitting ClawdNotch..."
    killall ClawdNotch 2>/dev/null || true
    sleep 1
    echo "  ✓ App quit"
fi

# --- Step 2: Remove app ---
if [ -d "/Applications/ClawdNotch.app" ]; then
    echo "→ Removing /Applications/ClawdNotch.app..."
    rm -rf "/Applications/ClawdNotch.app"
    echo "  ✓ App removed"
else
    echo "→ /Applications/ClawdNotch.app not found, skipping"
fi

# --- Step 3: Remove hook script ---
HOOK="$HOME/.claude/hooks/notchy-status.sh"
if [ -f "$HOOK" ]; then
    echo "→ Removing hook script..."
    rm -f "$HOOK"
    echo "  ✓ Hook removed"
else
    echo "→ Hook script not found, skipping"
fi

# --- Step 4: Remove hooks from settings.json ---
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q "notchy-status.sh" "$SETTINGS" 2>/dev/null; then
    echo "→ Removing hook entries from settings.json..."
    # Backup first
    BACKUP="$SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS" "$BACKUP"
    echo "  ✓ Backed up to $BACKUP"

    python3 -c "
import json

with open('$SETTINGS') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
for event in list(hooks.keys()):
    hooks[event] = [
        h for h in hooks[event]
        if not any(
            'notchy-status.sh' in hook.get('command', '')
            for hook in h.get('hooks', [])
        )
    ]
    if not hooks[event]:
        del hooks[event]

if not hooks:
    del settings['hooks']

with open('$SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
"
    echo "  ✓ Hook entries removed from settings.json"
else
    echo "→ No hook entries found in settings.json, skipping"
fi

# --- Step 5: Clean temp files ---
NOTCHY_DIR="${TMPDIR:-/tmp}/notchy-sessions"
if [ -d "$NOTCHY_DIR" ]; then
    echo "→ Cleaning temp files..."
    rm -rf "$NOTCHY_DIR"
    echo "  ✓ Temp files cleaned"
fi

echo ""
echo "  ✓ Claw'd Notch fully uninstalled."
echo "  Settings backup: $BACKUP"
echo ""
