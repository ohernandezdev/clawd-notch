#!/bin/bash
set -e

echo ""
echo "  🦀 Tars Notch Uninstaller"
echo "  ============================"
echo ""
echo "  This will:"
echo "    1. Quit the app (if running)"
echo "    2. Remove /Applications/TarsNotch.app"
echo "    3. Remove ~/.claude/hooks/tars-status.sh"
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

# --- Step 3: Remove hook script ---
HOOK="$HOME/.claude/hooks/tars-status.sh"
if [ -f "$HOOK" ]; then
    echo "→ Removing hook script..."
    rm -f "$HOOK"
    echo "  ✓ Hook removed"
else
    echo "→ Hook script not found, skipping"
fi

# --- Step 4: Remove hooks from settings.json ---
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q "tars-status.sh" "$SETTINGS" 2>/dev/null; then
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
            'tars-status.sh' in hook.get('command', '')
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
TARS_DIR="${TMPDIR:-/tmp}/tars-sessions"
if [ -d "$TARS_DIR" ]; then
    echo "→ Cleaning temp files..."
    rm -rf "$TARS_DIR"
    echo "  ✓ Temp files cleaned"
fi

echo ""
echo "  ✓ Tars Notch fully uninstalled."
echo "  Settings backup: $BACKUP"
echo ""
