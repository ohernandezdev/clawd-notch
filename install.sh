#!/bin/bash
set -e

# Tars Notch installer
# Builds the app, installs the hook, configures Claude Code settings, and launches.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TarsNotch.app"

echo ""
echo "  🦀 Tars Notch Installer"
echo "  ========================="
echo ""
echo "  This installer will:"
echo "    1. Build the app from source (Xcode)"
echo "    2. Copy TarsNotch.app to /Applications"
echo "    3. Install hook scripts for your AI coding agents"
echo "    4. Configure hooks in settings files"
echo "    5. Launch the app"
echo ""
echo "  Which AI coding agents do you use?"
echo "    [1] Claude Code only"
echo "    [2] GitHub Copilot CLI only"
echo "    [3] Both (default)"
echo ""
read -rp "  Choice [3]: " provider_choice
provider_choice="${provider_choice:-3}"

INSTALL_CLAUDE=false
INSTALL_COPILOT=false
case "$provider_choice" in
    1) INSTALL_CLAUDE=true ;;
    2) INSTALL_COPILOT=true ;;
    *) INSTALL_CLAUDE=true; INSTALL_COPILOT=true ;;
esac

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

# Full Xcode is required (not just Command Line Tools)
if ! xcodebuild -version &>/dev/null; then
    echo "  ✗ Full Xcode installation required (Command Line Tools alone won't work)."
    echo "    Install Xcode from the App Store, then run:"
    echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

xcodebuild -project "$SCRIPT_DIR/TarsNotch.xcodeproj" \
    -scheme TarsNotch \
    -configuration Release \
    -derivedDataPath "$SCRIPT_DIR/build" \
    CODE_SIGN_IDENTITY="-" \
    -quiet

if [ ! -d "$SCRIPT_DIR/build/Build/Products/Release/$APP_NAME" ]; then
    echo "  ✗ Build failed — $APP_NAME not found. Check xcodebuild output above."
    exit 1
fi

echo "  ✓ Built successfully"

# --- Step 2: Install app ---
echo "→ Installing to /Applications..."
if [ -d "/Applications/$APP_NAME" ]; then
    rm -rf "/Applications/$APP_NAME"
fi
cp -r "$SCRIPT_DIR/build/Build/Products/Release/$APP_NAME" "/Applications/$APP_NAME"
echo "  ✓ Installed to /Applications/$APP_NAME"

# --- Step 3: Install hooks ---

if [ "$INSTALL_CLAUDE" = true ]; then
    HOOK_SRC="$SCRIPT_DIR/hooks/tars-status.sh"
    HOOK_DST="$HOME/.claude/hooks/tars-status.sh"
    SETTINGS="$HOME/.claude/settings.json"
    HOOK_CMD="bash ~/.claude/hooks/tars-status.sh"

    echo "→ Installing Claude Code hooks..."
    mkdir -p "$HOME/.claude/hooks"
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    echo "  ✓ Hook installed to $HOOK_DST"

    echo "→ Configuring Claude Code settings..."
    if [ -f "$SETTINGS" ]; then
        BACKUP="$SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SETTINGS" "$BACKUP"
        echo "  ✓ Backed up settings to $BACKUP"

        if grep -q "tars-status.sh" "$SETTINGS" 2>/dev/null; then
            echo "  ✓ Hooks already configured in settings.json"
        else
            python3 -c "
import json
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
            echo "  ✓ Hooks added to $SETTINGS"
        fi
    else
        mkdir -p "$HOME/.claude"
        python3 -c "
import json
hook_entry = {'matcher': '', 'hooks': [{'type': 'command', 'command': '$HOOK_CMD', 'timeout': 3}]}
settings = {'hooks': {'PostToolUse': [hook_entry], 'Notification': [hook_entry], 'Stop': [hook_entry]}}
with open('$SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
"
        echo "  ✓ Created $SETTINGS with hooks"
    fi
fi

if [ "$INSTALL_COPILOT" = true ]; then
    COPILOT_HOOK_SRC="$SCRIPT_DIR/hooks/tars-status-copilot.sh"
    COPILOT_HOOK_DST="$HOME/.copilot/hooks/tars-status-copilot.sh"
    COPILOT_CONFIG="$HOME/.copilot/hooks/tars-notch.json"

    echo "→ Installing Copilot CLI hooks..."
    mkdir -p "$HOME/.copilot/hooks"
    cp "$COPILOT_HOOK_SRC" "$COPILOT_HOOK_DST"
    chmod +x "$COPILOT_HOOK_DST"
    echo "  ✓ Hook installed to $COPILOT_HOOK_DST"

    echo "→ Configuring Copilot CLI hooks..."
    if [ -f "$COPILOT_CONFIG" ] && grep -q "tars-status-copilot" "$COPILOT_CONFIG" 2>/dev/null; then
        echo "  ✓ Hooks already configured in $COPILOT_CONFIG"
    else
        python3 -c "
import json, os
config_path = '$COPILOT_CONFIG'
config = {'version': 1, 'hooks': {}}
if os.path.isfile(config_path):
    with open(config_path) as f:
        config = json.load(f)
hooks = config.setdefault('hooks', {})
hook_entry = {'type': 'command', 'bash': 'bash ~/.copilot/hooks/tars-status-copilot.sh', 'timeoutSec': 3}
for event in ['postToolUse', 'sessionEnd']:
    event_hooks = hooks.setdefault(event, [])
    if not any('tars-status-copilot' in str(h.get('bash','')) for h in event_hooks):
        event_hooks.append(hook_entry)
config['hooks'] = hooks
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
"
        echo "  ✓ Created $COPILOT_CONFIG"
    fi
fi

# --- Step 4: Launch ---
echo ""
read -rp "→ Launch Tars Notch now? [Y/n] " launch
if [[ "$launch" =~ ^[Nn]$ ]]; then
    echo "  ✓ Install complete. Launch manually: open /Applications/$APP_NAME"
else
    open "/Applications/$APP_NAME"
    echo "  ✓ Done! Tars is in your notch."
    echo "  Hover over the notch to see your AI coding sessions."
fi
echo ""
