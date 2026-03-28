# Security

## Threat Model

Claw'd Notch is a **local developer tool**. It runs entirely on your machine with no network access. The threat model focuses on preventing accidental exposure of sensitive information that passes through Claude Code sessions.

### What it reads

- **Hook event JSON** (via stdin): session ID, tool name, working directory, hook event type
- **Claude Code transcript** (JSONL): reads the last ~20KB to extract the most recent assistant message for status display
- **Session JSON files**: reads from `$TMPDIR/notchy-sessions/` to display session state

### What it writes

- **Session JSON files**: one per active session in `$TMPDIR/notchy-sessions/` (per-user, `chmod 700`)
- **macOS notifications**: generic text only ("Claude needs input" / "Task completed") — no message content

### What it does NOT do

- No network calls — the app never contacts any server
- No analytics or telemetry
- No data persistence beyond the current session (temp files are cleaned up)
- No access to other apps or system resources beyond what's listed above

## Privacy Controls

- **Privacy mode** (on by default): hides Claude's message content from the panel. Shows only tool names and status.
- **Generic notifications**: notifications never include message content, project paths, or working directories.
- **Secret filtering**: the hook script filters common secret patterns (API keys, tokens, JWTs) from displayed text.

## App Sandbox

This app is **not sandboxed**. It runs outside the macOS App Sandbox because it needs to:

1. Read files from `$TMPDIR` written by Claude Code hooks
2. Execute `osascript` for local macOS notifications

The app has **Hardened Runtime** enabled, which provides:
- Library validation
- Code signing enforcement
- Runtime protections against code injection

## Session ID Validation

Session IDs used as filenames are validated against `^[A-Za-z0-9_-]{1,128}$` and passed through `os.path.basename()` to prevent path traversal.

## Atomic File Writes

All JSON state files are written atomically (write to temp file, then `os.replace()`) to prevent corrupted reads.

## Reporting Vulnerabilities

If you find a security issue, please open a GitHub issue or email security concerns to the repository owner. This is a developer tool with a small attack surface, but all reports are taken seriously.

## Limitations

- The app is not code-signed with an Apple Developer ID (ad-hoc signed)
- The app is not notarized by Apple
- The transcript parser reads raw content — while secrets are filtered, novel secret formats may not be caught
- Session files in `$TMPDIR` are readable only by the current user, but any process running as that user can read them
