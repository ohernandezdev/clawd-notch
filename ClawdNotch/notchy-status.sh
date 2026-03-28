#!/bin/bash
# Claw'd Notch status hook — writes Claude Code session state to a per-user temp directory

NOTCHY_DIR="${TMPDIR:-/tmp}/notchy-sessions"
mkdir -p "$NOTCHY_DIR"
chmod 700 "$NOTCHY_DIR"

INPUT=$(cat)

echo "$INPUT" | python3 -c "
import sys, json, os, time, re, tempfile

d = json.load(sys.stdin)
sid = d.get('session_id', 'unknown')
hook = d.get('hook_event_name', d.get('hook_event', 'unknown'))

# --- Validate session_id (strict charset, no path traversal) ---
if not re.match(r'^[A-Za-z0-9_-]{1,128}$', sid):
    sid = 'invalid'
sid = os.path.basename(sid)
tool = d.get('tool_name', '')
cwd = d.get('cwd', d.get('working_directory', os.getcwd()))
transcript = d.get('transcript_path', '')

# --- Read last assistant message from transcript ---
last_claude_text = ''
if transcript and os.path.isfile(transcript):
    try:
        with open(transcript, 'rb') as f:
            # Read only last ~20KB (more aggressive)
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 20000))
            tail = f.read().decode('utf-8', errors='replace')

        lines = tail.strip().split('\n')
        for line in reversed(lines):
            try:
                entry = json.loads(line)
                msg = entry.get('message', {})
                if msg.get('role') == 'assistant':
                    content = msg.get('content', [])
                    if isinstance(content, list):
                        for part in content:
                            if isinstance(part, dict) and part.get('type') == 'text':
                                text = part['text'].strip()
                                if text and len(text) > 5:
                                    text_lines = [l.strip() for l in text.split('\n') if l.strip()]
                                    if text_lines:
                                        last_claude_text = text_lines[-1][:120]
                                    break
                    if last_claude_text:
                        break
            except:
                continue
    except:
        pass

# --- Basic secrets filter ---
import re as _re
_secret_patterns = [
    r'(?:sk|pk|api|key|token|secret|password|bearer)[_-]?[A-Za-z0-9]{20,}',
    r'ghp_[A-Za-z0-9]{36}',
    r'eyJ[A-Za-z0-9_-]{20,}',
]
for _pat in _secret_patterns:
    if _re.search(_pat, last_claude_text, _re.IGNORECASE):
        last_claude_text = '[redacted]'
        break

# --- Build tool description ---
desc = ''
ti = d.get('tool_input', {})
if not isinstance(ti, dict):
    ti = {}

if tool == 'Bash':
    cmd = ti.get('command', '')
    if cmd:
        cmd = cmd.split('&&')[0].split('|')[0].strip()
        desc = cmd[:80]
elif tool in ('Edit', 'MultiEdit'):
    fp = ti.get('file_path', '')
    desc = 'Editing ' + os.path.basename(fp) if fp else 'Editing'
elif tool == 'Write':
    fp = ti.get('file_path', '')
    desc = 'Writing ' + os.path.basename(fp) if fp else 'Writing'
elif tool == 'Read':
    fp = ti.get('file_path', '')
    desc = 'Reading ' + os.path.basename(fp) if fp else 'Reading'
elif tool == 'Grep':
    pat = ti.get('pattern', '')
    desc = 'Searching: ' + pat[:50] if pat else 'Searching'
elif tool == 'Glob':
    desc = 'Finding files'
elif tool == 'Agent':
    desc = ti.get('description', 'Subagent')[:60]
elif tool:
    desc = tool

# --- Status ---
status = 'working'

desc_lower = (last_claude_text or desc).lower()
if 'waiting for your input' in desc_lower or 'waiting for input' in desc_lower:
    status = 'waitingForInput'

if hook in ('SessionStart', 'session_start'):
    status = 'idle'
elif hook in ('Stop', 'stop', 'SessionEnd', 'session_end'):
    # Extract last assistant message (provided by Claude Code on Stop)
    lam = d.get('last_assistant_message', '')
    if lam:
        lines = [l.strip() for l in lam.split('\n') if l.strip()]
        lam_text = lines[-1][:150] if lines else ''
    else:
        lam_text = last_claude_text or desc
    # Write notification request for the app to pick up
    notif = {
        'project': os.path.basename(cwd),
        'message': lam_text or 'Done',
        'type': 'waitingForInput',
        'timestamp': int(time.time())
    }
    notif_dir = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'notchy-sessions')
    notif_path = os.path.join(notif_dir, '_notify_' + sid + '.json')
    tmpfd2, tmppath2 = tempfile.mkstemp(dir=notif_dir, suffix='.tmp')
    try:
        with os.fdopen(tmpfd2, 'w') as f2:
            json.dump(notif, f2)
        os.replace(tmppath2, notif_path)
    except:
        try: os.unlink(tmppath2)
        except: pass
    # Update session status to waitingForInput
    status = 'waitingForInput'
    last_claude_text = lam_text
elif hook in ('Notification', 'notification'):
    ntype = str(d.get('notification_type', d.get('type', '')))
    if 'waiting' in ntype or 'input' in ntype or 'question' in ntype:
        status = 'waitingForInput'
    elif 'complete' in ntype or 'done' in ntype or 'finished' in ntype:
        status = 'taskCompleted'

# --- Project name ---
project = os.path.basename(cwd)
if '/.claude/worktrees/' in cwd:
    parts = cwd.split('/.claude/worktrees/')
    if len(parts) > 1:
        wt_name = parts[1].split('/')[0]
        project = project + ' (' + wt_name + ')'

# --- macOS notification on transition to waitingForInput ---
send_notification = False
outpath = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'notchy-sessions', sid + '.json')
if status == 'waitingForInput':
    try:
        with open(outpath) as f:
            prev = json.load(f)
        if prev.get('status') != 'waitingForInput':
            send_notification = True
    except:
        send_notification = True

# --- Write ---
out = {
    'session_id': sid,
    'project_name': project,
    'working_directory': cwd,
    'status': status,
    'tool_name': tool,
    'hook_event': hook,
    'tool_desc': desc,
    'last_message': last_claude_text or desc,
    'updated_at': int(time.time())
}

# --- Atomic write (tmp file + os.replace) ---
tmpfd, tmppath = tempfile.mkstemp(dir=os.path.join(os.environ.get('TMPDIR', '/tmp'), 'notchy-sessions'), suffix='.tmp')
try:
    with os.fdopen(tmpfd, 'w') as f:
        json.dump(out, f, indent=2)
    os.replace(tmppath, outpath)
except:
    try: os.unlink(tmppath)
    except: pass

# Notifications are handled by the Claw'd Notch app
" 2>/dev/null
