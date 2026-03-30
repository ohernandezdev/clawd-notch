#!/usr/bin/env python3
"""Claw'd Notch status hook for GitHub Copilot CLI"""
import sys, json, os, time, re, tempfile

d = json.load(sys.stdin)

# Copilot uses camelCase, map to our format
sid = d.get('sessionId', d.get('session_id', 'unknown'))
cwd = d.get('cwd', os.getcwd())
tool = d.get('toolName', d.get('tool_name', ''))
hook = ''
reason = d.get('reason', '')
tool_result = d.get('toolResult', {})
tool_args = d.get('toolArgs', d.get('tool_input', {}))

if not isinstance(tool_args, dict):
    try:
        tool_args = json.loads(tool_args) if isinstance(tool_args, str) else {}
    except:
        tool_args = {}

# Detect hook event
if reason:
    hook = 'Stop'
elif tool:
    hook = 'PostToolUse'
else:
    hook = 'unknown'

# Validate session_id
if not re.match(r'^[A-Za-z0-9_-]{1,128}$', sid):
    sid = 'invalid'
sid = os.path.basename(sid)

# --- Build tool description ---
desc = ''
ti = tool_args

tool_map = {
    # Copilot CLI built-in tools
    'bash': 'Bash', 'shell': 'Bash', 'read_bash': 'Bash',
    'edit': 'Edit', 'multi_edit': 'MultiEdit',
    'write': 'Write', 'create_file': 'Write',
    'view': 'Read', 'read': 'Read', 'read_file': 'Read',
    'grep': 'Grep', 'search': 'Grep',
    'glob': 'Glob', 'find_files': 'Glob', 'list_files': 'Glob',
    'agent': 'Agent', 'report_intent': 'Agent',
    'ask_user': 'Ask',
    # Claude Code tools (if used as fork)
    'Edit': 'Edit', 'MultiEdit': 'MultiEdit',
    'Write': 'Write', 'Read': 'Read',
    'Bash': 'Bash', 'Grep': 'Grep', 'Glob': 'Glob',
    'Agent': 'Agent', 'WebSearch': 'WebSearch', 'WebFetch': 'WebFetch',
    'TodoRead': 'Task', 'TodoWrite': 'Task',
    'NotebookRead': 'Read', 'NotebookEdit': 'Edit',
}
mapped_tool = tool_map.get(tool.lower(), tool.capitalize() if tool else '')

if tool.lower() in ('bash', 'shell', 'read_bash'):
    cmd = ti.get('command', '')
    if cmd:
        cmd = cmd.split('&&')[0].split('|')[0].strip()
        desc = cmd[:80]
elif tool.lower() in ('edit', 'edit_file'):
    fp = ti.get('file_path', ti.get('path', ''))
    desc = 'Editing ' + os.path.basename(fp) if fp else 'Editing'
elif tool.lower() == 'multi_edit':
    fp = ti.get('file_path', ti.get('path', ''))
    desc = 'Editing ' + os.path.basename(fp) if fp else 'Editing'
elif tool.lower() in ('write', 'create_file'):
    fp = ti.get('file_path', ti.get('path', ''))
    desc = 'Writing ' + os.path.basename(fp) if fp else 'Writing'
elif tool.lower() in ('view', 'read', 'read_file'):
    fp = ti.get('file_path', ti.get('path', ''))
    desc = 'Reading ' + os.path.basename(fp) if fp else 'Reading'
elif tool.lower() in ('grep', 'search'):
    pat = ti.get('pattern', ti.get('query', ''))
    desc = 'Searching: ' + pat[:50] if pat else 'Searching'
elif tool.lower() in ('glob', 'find_files', 'list_files'):
    desc = 'Finding files'
elif tool.lower() == 'report_intent':
    desc = ti.get('intent', '')[:80]
elif tool.lower() == 'ask_user':
    desc = 'Waiting for input'
elif tool:
    desc = mapped_tool or tool

last_message = desc

# --- Status ---
status = 'working'
if hook == 'Stop':
    status = 'waitingForInput'
    notif = {
        'project': os.path.basename(cwd),
        'message': last_message or 'Done',
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

# --- Secrets filter ---
_secret_patterns = [
    r'(?:sk|pk|api|key|token|secret|password|bearer)[_-]?[A-Za-z0-9]{20,}',
    r'ghp_[A-Za-z0-9]{36}',
    r'eyJ[A-Za-z0-9_-]{20,}',
]
for _pat in _secret_patterns:
    if re.search(_pat, last_message, re.IGNORECASE):
        last_message = '[redacted]'
        break
for _pat in _secret_patterns:
    if re.search(_pat, desc, re.IGNORECASE):
        desc = '[redacted]'
        break

# --- Project name ---
project = os.path.basename(cwd)

# --- Write ---
notchy_dir = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'notchy-sessions')
os.makedirs(notchy_dir, mode=0o700, exist_ok=True)
outpath = os.path.join(notchy_dir, sid + '.json')
out = {
    'session_id': sid,
    'project_name': project,
    'working_directory': cwd,
    'status': status,
    'tool_name': mapped_tool,
    'hook_event': hook,
    'tool_desc': desc,
    'last_message': last_message,
    'updated_at': int(time.time()),
    'provider': 'copilot'
}

tmpfd, tmppath = tempfile.mkstemp(dir=notchy_dir, suffix='.tmp')
try:
    with os.fdopen(tmpfd, 'w') as f:
        json.dump(out, f, indent=2)
    os.replace(tmppath, outpath)
except:
    try: os.unlink(tmppath)
    except: pass
