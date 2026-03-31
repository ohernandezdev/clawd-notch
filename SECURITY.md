# Security & Privacy

Tars Notch is a developer tool that reads your AI coding agent's hook events to display session status. Here's the full security picture.

## What it accesses

| Data | How | Why |
|------|-----|-----|
| Hook event JSON | Received via stdin in `tars-status.sh` | Session ID, tool name, working directory |
| Transcript JSONL | Reads last ~20KB of `transcript_path` | Extracts last assistant message |
| `$TMPDIR/tars-sessions/` | Reads/writes JSON files | Session state persistence |
| `localhost:7483` | HTTP server (loopback only) | Instant updates from hooks to app |
| `~/.claude/settings.json` | Read + safe merge on install | Adds hook entries (backs up first) |
| `~/.copilot/settings.json` | Read + safe merge on install | Same for Copilot CLI |

## What it does NOT access

- No network calls to external servers
- No Accessibility permissions
- No screen recording or input monitoring
- No keychain or credential access
- No file system access outside `$TMPDIR` and hook paths
- No Apple Events or automation entitlements

## HTTP server

The app runs a local HTTP server on `localhost:7483` (loopback only — not accessible from the network). It accepts:

- `POST /hook` — session state updates from the hook script
- `POST /permission` — permission approval requests (holds connection until user responds)
- `GET /health` — health check

The server binds to `127.0.0.1` only. No TLS (unnecessary for loopback).

## Permission approval flow

When Claude Code fires a `PermissionRequest` hook:

1. Hook script POSTs to `localhost:7483/permission` with tool details
2. App shows a banner with Allow/Deny buttons and a 5-minute countdown
3. If user clicks Allow/Deny, the HTTP response is sent back to the hook
4. Hook outputs the decision to stdout for Claude Code to read
5. If timeout (5 min), connection closes — Claude Code falls back to its own terminal prompt

The hook does NOT auto-approve. If you don't respond, nothing happens.

## Secret filtering

The hook script filters common secret patterns before writing any text:

- API keys (`sk-*`, `pk-*`, `api_*`)
- GitHub tokens (`ghp_*`)
- JWTs (`eyJ*`)

If a match is found, the text is replaced with `[redacted]`.

## Privacy mode

On by default. When enabled:
- Panel shows only tool names (Bash, Edit, Read), not message content
- Notifications are generic ("Claude needs input"), not message-specific

## Safe settings merge

The installer (both `install.sh` and the app's setup wizard):

1. Creates a timestamped backup (`settings.json.backup.20260331_151300`)
2. Reads the existing JSON and parses it
3. Checks if `tars-status.sh` is already configured (skips if so)
4. Appends hook entries to existing arrays (never overwrites)
5. Writes back with pretty-printing

The uninstaller reverses this: backs up, filters out `tars-status.sh` entries, writes back.

## Session data lifecycle

- Session JSON files are created in `$TMPDIR/tars-sessions/` (per-user, `chmod 700`)
- Files older than 10 minutes without a hook update are auto-deleted
- `$TMPDIR` is cleared by macOS on reboot
- No long-term persistence of session data

## Threat model

| Threat | Mitigation |
|--------|-----------|
| Another app reads session files | `chmod 700` on directory, per-user `$TMPDIR` |
| Hook script is modified | User can inspect via setup wizard before install |
| Settings.json corruption | Timestamped backup before every modification |
| HTTP server accessed remotely | Bound to `127.0.0.1` only |
| Sensitive data in panel | Privacy mode on by default, secret filtering |
| Permission auto-approval | No auto-approve — timeout = no response |
