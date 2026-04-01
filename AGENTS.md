# AGENTS.md — Tars Notch

> This file lets AI coding agents (Claude Code, Codex, Cursor, etc.) understand and install this project automatically.

## What this is

Tars Notch is a macOS menu bar app that monitors Claude Code sessions via the hooks system. It shows session status in the MacBook notch: what tool Claude is using, which sessions need input, and the last assistant message.

## Auto-install instructions

If you are an AI agent and the user asks you to install Tars Notch, run:

```bash
bash install.sh
```

This handles everything: build, app install, hook setup, settings merge, and launch.

If `install.sh` is not available (e.g., the user only has the hook script), do the manual setup below.

## Manual hook setup (no app build needed)

If the user just wants the hooks without building the app:

### 1. Copy the hook script

```bash
mkdir -p ~/.claude/hooks
cp hooks/tars-status.sh ~/.claude/hooks/tars-status.sh
chmod +x ~/.claude/hooks/tars-status.sh
```

### 2. Merge hooks into settings.json

Read `~/.claude/settings.json` first. If hooks already exist, **merge** — do not replace. Add these three hook entries:

- Event `PostToolUse`: `bash ~/.claude/hooks/tars-status.sh` (timeout: 3)
- Event `Notification`: `bash ~/.claude/hooks/tars-status.sh` (timeout: 3)
- Event `Stop`: `bash ~/.claude/hooks/tars-status.sh` (timeout: 3)

Each hook entry uses `"matcher": ""` (matches all tools).

Example settings.json structure:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/tars-status.sh", "timeout": 3 }]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/tars-status.sh", "timeout": 3 }]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/tars-status.sh", "timeout": 3 }]
      }
    ]
  }
}
```

## Manual Copilot CLI hook setup

### 1. Copy the hook scripts

```bash
mkdir -p ~/.copilot/hooks
cp hooks/tars-status-copilot.py ~/.copilot/hooks/tars-status-copilot.py
cp hooks/tars-status-copilot.sh ~/.copilot/hooks/tars-status-copilot.sh
chmod +x ~/.copilot/hooks/tars-status-copilot.py ~/.copilot/hooks/tars-status-copilot.sh
```

### 2. Create the hook config file

Copilot CLI reads hook configs from individual JSON files in `~/.copilot/hooks/` (not from `settings.json`). Create `~/.copilot/hooks/tars-notch.json`:

```json
{
  "hooks": {
    "PostToolUse": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.copilot/hooks/tars-status-copilot.sh", "timeout": 3 }] }],
    "Notification": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.copilot/hooks/tars-status-copilot.sh", "timeout": 3 }] }],
    "Stop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.copilot/hooks/tars-status-copilot.sh", "timeout": 3 }] }],
    "SessionStart": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.copilot/hooks/tars-status-copilot.sh", "timeout": 3 }] }],
    "SessionEnd": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.copilot/hooks/tars-status-copilot.sh", "timeout": 3 }] }],
    "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.copilot/hooks/tars-status-copilot.sh", "timeout": 3 }] }],
    "SubagentStart": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.copilot/hooks/tars-status-copilot.sh", "timeout": 3 }] }],
    "SubagentStop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.copilot/hooks/tars-status-copilot.sh", "timeout": 3 }] }],
    "PermissionRequest": [{ "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.copilot/hooks/tars-status-copilot.sh", "timeout": 300 }] }]
  }
}
```

Restart your Copilot CLI session after creating this file.

## Build from source

```bash
xcodebuild -project TarsNotch.xcodeproj -scheme TarsNotch -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY="-"
```

The built app is at `build/Build/Products/Release/TarsNotch.app`.

## Architecture overview

- **Language**: Swift, SwiftUI, AppKit
- **Dependency**: SwiftTerm (via SPM)
- **Data flow**: Hook script writes JSON to `$TMPDIR/tars-sessions/` (per-user, chmod 700). App polls every 2 seconds.
- **Hook script**: `hooks/tars-status.sh` — receives hook JSON on stdin, extracts session state, writes to `$TMPDIR/tars-sessions/{session_id}.json`
- **Entitlements**: None required (sandbox-free)

## Code conventions

- No tests or linting configured
- SwiftUI for panel UI, AppKit for window management
- `@Observable` macro for state management
- Xcode project (not SPM package)

## Requirements

- macOS 15.0+
- Xcode or Xcode Command Line Tools
- Python 3 (for hook script, pre-installed on macOS)
