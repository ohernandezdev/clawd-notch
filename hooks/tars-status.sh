#!/bin/bash
# Tars Notch HTTP hook — sends data directly to the app's HTTP server for instant updates
# Falls back to file-based JSON if the server is not running

TARS_DIR="${TMPDIR:-/tmp}/tars-sessions"
mkdir -p "$TARS_DIR"
chmod 700 "$TARS_DIR"

INPUT=$(cat)
export TARS_INPUT_FILE=$(mktemp "${TARS_DIR}/.input.XXXXXX")
echo "$INPUT" > "$TARS_INPUT_FILE"

python3 << 'PYEOF'
import sys, json, os, time, re, tempfile
from urllib.request import urlopen, Request
from urllib.error import URLError

_input_file = os.environ['TARS_INPUT_FILE']
with open(_input_file) as _f:
    d = json.load(_f)
os.unlink(_input_file)
# Support both snake_case (Claude Code) and camelCase (Copilot CLI)
def g(snake, camel=''):
    if not camel:
        camel = ''.join(w.capitalize() if i else w for i, w in enumerate(snake.split('_')))
    return d.get(snake, d.get(camel, ''))

sid = g('session_id') or 'unknown'
hook = g('hook_event_name') or g('hook_event') or 'unknown'

if not re.match(r'^[A-Za-z0-9_-]{1,128}$', sid):
    sid = 'invalid'
sid = os.path.basename(sid)
tool = g('tool_name')
cwd = g('cwd') or g('working_directory') or os.getcwd()
transcript = g('transcript_path')
permission_mode = g('permission_mode')
agent_id = g('agent_id')
agent_type = g('agent_type')
model = g('model', 'model')

# --- Read last assistant message from transcript ---
last_claude_text = ''
if transcript and os.path.isfile(transcript):
    try:
        with open(transcript, 'rb') as f:
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

# --- Secrets filter ---
_secret_patterns = [
    r'(?:sk|pk|api|key|token|secret|password|bearer)[_-]?[A-Za-z0-9]{20,}',
    r'ghp_[A-Za-z0-9]{36}',
    r'eyJ[A-Za-z0-9_-]{20,}',
]
for _pat in _secret_patterns:
    if re.search(_pat, last_claude_text, re.IGNORECASE):
        last_claude_text = '[redacted]'
        break

# --- Build tool description ---
desc = ''
ti = d.get('tool_input', d.get('toolInput', d.get('tool_args', d.get('toolArgs', {}))))
if not isinstance(ti, dict):
    ti = {}

if tool == 'Bash':
    cmd = ti.get('command', '')
    if cmd: desc = cmd.split('&&')[0].split('|')[0].strip()[:80]
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
elif tool == 'Glob': desc = 'Finding files'
elif tool == 'Agent': desc = ti.get('description', 'Subagent')[:60]
elif tool == 'WebSearch': desc = 'Searching: ' + ti.get('query', '')[:50]
elif tool == 'WebFetch': desc = 'Fetching: ' + ti.get('url', '')[:50]
elif tool in ('TaskCreate', 'TaskUpdate', 'TaskGet', 'TaskList'): desc = 'Managing tasks'
elif tool == 'Skill': desc = 'Running /' + ti.get('skill', 'skill')
elif tool == 'SendMessage': desc = 'Messaging agent'
elif tool == 'AskUserQuestion': desc = 'Asking user'
elif tool == 'ToolSearch': desc = 'Loading tools'
elif tool in ('EnterPlanMode', 'ExitPlanMode'): desc = 'Planning'
elif tool: desc = tool

# --- Status ---
status = 'working'
desc_lower = (last_claude_text or desc).lower()
if 'waiting for your input' in desc_lower or 'waiting for input' in desc_lower:
    status = 'waitingForInput'
    # Replace generic message with actual last Claude text from transcript
    if last_claude_text and ('waiting' in last_claude_text.lower()):
        # The last_claude_text IS the generic message — re-read transcript for real content
        if transcript and os.path.isfile(transcript):
            try:
                with open(transcript, 'rb') as f:
                    f.seek(0, 2)
                    sz = f.tell()
                    f.seek(max(0, sz - 30000))
                    tail2 = f.read().decode('utf-8', errors='replace')
                for line2 in reversed(tail2.strip().split('\n')):
                    try:
                        e2 = json.loads(line2)
                        m2 = e2.get('message', {})
                        if m2.get('role') == 'assistant':
                            c2 = m2.get('content', [])
                            if isinstance(c2, list):
                                for p2 in c2:
                                    if isinstance(p2, dict) and p2.get('type') == 'text':
                                        t2 = p2['text'].strip()
                                        if t2 and len(t2) > 5 and 'waiting' not in t2.lower():
                                            tlines = [l.strip() for l in t2.split('\n') if l.strip()]
                                            if tlines:
                                                last_claude_text = tlines[-1][:150]
                                            break
                            if last_claude_text and 'waiting' not in last_claude_text.lower():
                                break
                    except: continue
            except: pass

# --- Tool history ---
tars_dir = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'tars-sessions')
outpath = os.path.join(tars_dir, sid + '.json')
tool_history = []
prev_data = {}
try:
    with open(outpath) as f:
        prev_data = json.load(f)
    tool_history = prev_data.get('tool_history', [])
except: pass

# --- Handle events ---
if hook == 'SessionStart':
    status = 'idle'
    model = d.get('model', model)
    desc = 'Session ' + d.get('source', '')
    tool_history = []
elif hook == 'SessionEnd':
    status = 'idle'
    desc = 'Session ended'
elif hook == 'Stop':
    lam = d.get('last_assistant_message', d.get('lastAssistantMessage', ''))
    if lam:
        lns = [l.strip() for l in lam.split('\n') if l.strip()]
        last_claude_text = lns[-1][:150] if lns else last_claude_text
    status = 'waitingForInput'
    # Write notification file
    notif = {'project': os.path.basename(cwd), 'message': last_claude_text or 'Done', 'type': 'waitingForInput', 'timestamp': int(time.time())}
    notif_path = os.path.join(tars_dir, '_notify_' + sid + '.json')
    tmpfd2, tmppath2 = tempfile.mkstemp(dir=tars_dir, suffix='.tmp')
    try:
        with os.fdopen(tmpfd2, 'w') as f2: json.dump(notif, f2)
        os.replace(tmppath2, notif_path)
    except:
        try: os.unlink(tmppath2)
        except: pass
elif hook == 'Notification':
    ntype = str(d.get('notification_type', d.get('notificationType', '')))
    nmsg = d.get('message', d.get('text', ''))
    nmsg_lower = nmsg.lower()
    if 'waiting' in ntype or 'input' in ntype or 'waiting' in nmsg_lower: status = 'waitingForInput'
    elif 'complete' in ntype or 'done' in ntype or 'complete' in nmsg_lower: status = 'taskCompleted'
    # Don't overwrite real message with generic "Claude is waiting for your input"
    if nmsg and 'waiting for your input' not in nmsg_lower and 'waiting for input' not in nmsg_lower:
        last_claude_text = nmsg[:120]
    # If we'd show generic, keep the previous message instead
    elif not last_claude_text or 'waiting' in last_claude_text.lower():
        last_claude_text = prev_data.get('last_message', '') or last_claude_text
elif hook == 'UserPromptSubmit':
    status = 'working'
    prompt = d.get('prompt', '')
    desc = 'User: ' + prompt[:60] if prompt else 'User sent prompt'
    last_claude_text = desc
elif hook == 'SubagentStart':
    status = 'working'
    desc = 'Started ' + d.get('agent_type', 'agent') + ' agent'
elif hook == 'SubagentStop':
    status = 'working'
    desc = d.get('agent_type', 'agent') + ' agent finished'
elif hook == 'PermissionRequest':
    status = 'waitingForInput'
    desc = 'Permission: ' + tool

# --- Tool history ---
if hook in ('PostToolUse', 'PostToolUseFailure') and tool:
    tool_history.append({'tool': tool, 'desc': desc[:80], 'time': int(time.time()), 'ok': hook == 'PostToolUse'})
    tool_history = tool_history[-50:]

active_agents = prev_data.get('active_agents', 0)
if hook == 'SubagentStart': active_agents += 1
elif hook == 'SubagentStop': active_agents = max(0, active_agents - 1)

project = os.path.basename(cwd)
if '/.claude/worktrees/' in cwd:
    parts = cwd.split('/.claude/worktrees/')
    if len(parts) > 1: project += ' (' + parts[1].split('/')[0] + ')'

out = {
    'session_id': sid,
    'project_name': project,
    'working_directory': cwd,
    'status': status,
    'tool_name': tool,
    'hook_event': hook,
    'tool_desc': desc,
    'last_message': last_claude_text or desc,
    'updated_at': int(time.time()),
    'permission_mode': permission_mode,
    'agent_type': agent_type,
    'model': model or prev_data.get('model', ''),
    'active_agents': active_agents,
    'tool_history': tool_history,
    'tool_count': len(tool_history),
}

# --- Try HTTP first (instant) ---
http_sent = False
try:
    payload = json.dumps(out).encode()
    req = Request('http://127.0.0.1:7483/hook', data=payload, method='POST')
    req.add_header('Content-Type', 'application/json')
    resp = urlopen(req, timeout=1)
    http_sent = resp.status == 200
except:
    pass

# --- Permission request: hold connection and wait for decision ---
if hook == 'PermissionRequest':
    perm_payload = json.dumps({
        'session_id': sid,
        'project_name': project,
        'tool_name': tool,
        'tool_input': ti,
    }).encode()
    try:
        req = Request('http://127.0.0.1:7483/permission', data=perm_payload, method='POST')
        req.add_header('Content-Type', 'application/json')
        resp = urlopen(req, timeout=28)
        body = resp.read().decode()
        decision = json.loads(body)
        approved = decision.get('decision', 'approve') == 'approve'
        if approved:
            print(json.dumps({
                'hookSpecificOutput': {
                    'hookEventName': 'PermissionRequest',
                    'decision': {'behavior': 'allow'}
                }
            }))
        else:
            print(json.dumps({
                'hookSpecificOutput': {
                    'hookEventName': 'PermissionRequest',
                    'decision': {'behavior': 'deny', 'message': decision.get('reason', 'Denied from Tars Notch')}
                }
            }))
    except:
        pass  # Timeout = auto-approve (no output = continue)

# --- Always write file as fallback ---
tmpfd, tmppath = tempfile.mkstemp(dir=tars_dir, suffix='.tmp')
try:
    with os.fdopen(tmpfd, 'w') as f:
        json.dump(out, f, indent=2)
    os.replace(tmppath, outpath)
except:
    try: os.unlink(tmppath)
    except: pass
PYEOF
