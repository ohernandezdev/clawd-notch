#!/bin/bash
set -e

# Tars Notch installer
# Builds the app, installs the hook, configures settings, and launches.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TarsNotch.app"
HOOK_FILE="tars-status.sh"
EVENTS='["PostToolUse","Notification","Stop","SessionStart","SessionEnd","UserPromptSubmit","SubagentStart","SubagentStop"]'
PERM_EVENT="PermissionRequest"

echo ""
echo "  Tars Notch Installer"
echo "  ========================="
echo ""
echo "  This installer will:"
echo "    1. Build the app from source (Xcode)"
echo "    2. Copy TarsNotch.app to /Applications"
echo "    3. Install hook script + configure settings"
echo "    4. Launch the app"
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
echo "  Will do:"
echo "    - Build TarsNotch.app from source"
echo "    - Install to /Applications"
if [ "$INSTALL_CLAUDE" = true ]; then
echo "    - Install hook to ~/.claude/hooks/tars-status.sh"
echo "    - Add 9 hook events to ~/.claude/settings.json (backup first)"
fi
if [ "$INSTALL_COPILOT" = true ]; then
echo "    - Install hook to ~/.copilot/hooks/tars-status.sh"
echo "    - Add 9 hook events to ~/.copilot/settings.json (backup first)"
fi
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
    echo "  ✗ Build failed — $APP_NAME not found."
    exit 1
fi

echo "  ✓ Built successfully"

# --- Step 2: Install app ---
echo "→ Installing to /Applications..."
[ -d "/Applications/$APP_NAME" ] && rm -rf "/Applications/$APP_NAME"
cp -r "$SCRIPT_DIR/build/Build/Products/Release/$APP_NAME" "/Applications/$APP_NAME"
echo "  ✓ Installed to /Applications/$APP_NAME"

# --- Step 3: Install hooks (safe merge into existing settings) ---

install_hooks() {
    local PROVIDER="$1"       # "Claude Code" or "Copilot CLI"
    local CONFIG_DIR="$2"     # ~/.claude or ~/.copilot
    local HOOK_DIR="$CONFIG_DIR/hooks"
    local SETTINGS="$CONFIG_DIR/settings.json"
    local HOOK_CMD="bash $HOOK_DIR/$HOOK_FILE"

    echo "→ Installing $PROVIDER hooks..."
    mkdir -p "$HOOK_DIR"
    cp "$SCRIPT_DIR/hooks/$HOOK_FILE" "$HOOK_DIR/$HOOK_FILE"
    chmod +x "$HOOK_DIR/$HOOK_FILE"
    echo "  ✓ Hook installed to $HOOK_DIR/$HOOK_FILE"

    echo "→ Configuring $PROVIDER settings..."

    # Backup existing settings
    if [ -f "$SETTINGS" ]; then
        BACKUP="$SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SETTINGS" "$BACKUP"
        echo "  ✓ Backed up to $BACKUP"

        if grep -q "tars-status.sh" "$SETTINGS" 2>/dev/null; then
            echo "  ✓ Hooks already configured"
            return
        fi
    fi

    # Safe merge: read existing JSON, append our hooks, write back
    python3 << PYEOF
import json, os

settings_path = "$SETTINGS"
hook_cmd = "$HOOK_CMD"

# Read existing or create new
settings = {}
if os.path.isfile(settings_path):
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except:
        pass

hooks = settings.setdefault('hooks', {})

# Standard events (timeout 3s)
standard_entry = {'matcher': '', 'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 3}]}
for event in $EVENTS:
    event_hooks = hooks.setdefault(event, [])
    # Don't duplicate
    already = any(
        any('tars-status.sh' in str(h.get('command', '')) for h in entry.get('hooks', []))
        for entry in event_hooks if isinstance(entry, dict)
    )
    if not already:
        event_hooks.append(standard_entry)

# PermissionRequest (timeout 300s for user approval)
perm_entry = {'matcher': '', 'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 300}]}
perm_hooks = hooks.setdefault('$PERM_EVENT', [])
already_perm = any(
    any('tars-status.sh' in str(h.get('command', '')) for h in entry.get('hooks', []))
    for entry in perm_hooks if isinstance(entry, dict)
)
if not already_perm:
    perm_hooks.append(perm_entry)

settings['hooks'] = hooks

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
PYEOF

    echo "  ✓ Hooks added to $SETTINGS"
}

[ "$INSTALL_CLAUDE" = true ] && install_hooks "Claude Code" "$HOME/.claude"
[ "$INSTALL_COPILOT" = true ] && install_hooks "Copilot CLI" "$HOME/.copilot"

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
