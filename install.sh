#!/bin/bash
set -e

# Claw'd Notch installer
# Builds the app, installs the hook, configures Claude Code settings, and launches.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SRC="$SCRIPT_DIR/hooks/notchy-status.sh"
HOOK_DST="$HOME/.claude/hooks/notchy-status.sh"
SETTINGS="$HOME/.claude/settings.json"
APP_NAME="ClawdNotch.app"

echo ""
echo "  🦀 Claw'd Notch Installer"
echo "  ========================="
echo ""
echo "  This installer will:"
echo "    1. Build the app from source (Xcode)"
echo "    2. Copy ClawdNotch.app to /Applications"
echo "    3. Install a hook script to ~/.claude/hooks/"
echo "    4. Add hooks to ~/.claude/settings.json"
echo "    5. Launch the app"
echo ""
echo "  Your existing settings.json will be backed up first."
echo ""
read -rp "  Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "  Aborted."
    exit 0
fi
echo ""

# --- Step 1: Build ---
echo "→ Building from source..."
if ! command -v xcodebuild &>/dev/null; then
    echo "  ✗ xcodebuild not found. Install Xcode Command Line Tools:"
    echo "    xcode-select --install"
    exit 1
fi

xcodebuild -project "$SCRIPT_DIR/ClawdNotch.xcodeproj" \
    -scheme ClawdNotch \
    -configuration Release \
    -derivedDataPath "$SCRIPT_DIR/build" \
    CODE_SIGN_IDENTITY="-" \
    -quiet 2>&1 | tail -1

echo "  ✓ Built successfully"

# --- Step 2: Install app ---
echo "→ Installing to /Applications..."
if [ -d "/Applications/$APP_NAME" ]; then
    rm -rf "/Applications/$APP_NAME"
fi
cp -r "$SCRIPT_DIR/build/Build/Products/Release/$APP_NAME" "/Applications/$APP_NAME"
echo "  ✓ Installed to /Applications/$APP_NAME"

# --- Step 3: Install hook script ---
echo "→ Installing hook script..."
mkdir -p "$HOME/.claude/hooks"
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"
echo "  ✓ Hook installed to $HOOK_DST"

# --- Step 4: Configure Claude Code settings ---
echo "→ Configuring Claude Code hooks..."

HOOK_CMD="bash ~/.claude/hooks/notchy-status.sh"

if [ -f "$SETTINGS" ]; then
    # Backup existing settings
    BACKUP="$SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS" "$BACKUP"
    echo "  ✓ Backed up settings to $BACKUP"

    # Check if hook is already configured
    if grep -q "notchy-status.sh" "$SETTINGS" 2>/dev/null; then
        echo "  ✓ Hooks already configured in settings.json"
    else
        # Merge hooks into existing settings using python3
        python3 -c "
import json, sys

with open('$SETTINGS') as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})
hook_entry = {'matcher': '', 'hooks': [{'type': 'command', 'command': '$HOOK_CMD', 'timeout': 3}]}

for event in ['PostToolUse', 'Notification', 'Stop']:
    event_hooks = hooks.setdefault(event, [])
    event_hooks.append(hook_entry)

with open('$SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
"
        echo "  ✓ Hooks added to $SETTINGS (merged with existing config)"
    fi
else
    # Create new settings file
    mkdir -p "$HOME/.claude"
    python3 -c "
import json

hook_entry = {'matcher': '', 'hooks': [{'type': 'command', 'command': '$HOOK_CMD', 'timeout': 3}]}
settings = {
    'hooks': {
        'PostToolUse': [hook_entry],
        'Notification': [hook_entry],
        'Stop': [hook_entry]
    }
}

with open('$SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
"
    echo "  ✓ Created $SETTINGS with hooks"
fi

# --- Step 5: Launch ---
echo ""
read -rp "→ Launch Claw'd Notch now? [Y/n] " launch
if [[ "$launch" =~ ^[Nn]$ ]]; then
    echo "  ✓ Install complete. Launch manually: open /Applications/$APP_NAME"
else
    open "/Applications/$APP_NAME"
    echo "  ✓ Done! Claw'd is in your notch."
    echo "  Hover over the notch to see your Claude Code sessions."
fi
echo ""
