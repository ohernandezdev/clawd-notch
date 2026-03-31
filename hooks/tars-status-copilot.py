#!/usr/bin/env python3
"""Tars Notch status hook for GitHub Copilot CLI"""
import sys, json, os, time, re, tempfile

try:
    from urllib.request import urlopen, Request
except:
    urlopen = None

d = json.load(sys.stdin)

# === RAW EVENT LOG ===
log_dir = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'tars-sessions')
os.makedirs(log_dir, mode=0o700, exist_ok=True)
log_path = os.path.join(log_dir, '_copilot_raw_events.jsonl')
try:
    with open(log_path, 'a') as lf:
        lf.write(json.dumps({'_ts': time.time(), '_env_hook': os.environ.get('COPILOT_HOOK_EVENT', ''), 'data': d}) + '\n')
except:
    pass

sid = d.get('sessionId', d.get('session_id', 'unknown'))
cwd = d.get('cwd', os.getcwd())
tool = d.get('toolName', d.get('tool_name', ''))
reason = d.get('reason', '')
tool_result = d.get('toolResult', d.get('tool_response', {}))
tool_args = d.get('toolArgs', d.get('tool_input', {}))

raw_tool_args = d.get('toolArgs', d.get('tool_input', {}))
if not isinstance(tool_args, dict):
    try:
        tool_args = json.loads(tool_args) if isinstance(tool_args, str) else {}
    except:
        tool_args = {}
if not isinstance(tool_result, dict):
    tool_result = {}

if not re.match(r'^[A-Za-z0-9_-]{1,128}$', sid):
    sid = 'invalid'
sid = os.path.basename(sid)

# Detect hook event from JSON structure
has_tool_result = 'toolResult' in d or 'tool_response' in d
if d.get('stopReason'):
    hook = 'Stop'
elif d.get('reason'):
    hook = 'SessionEnd'
elif d.get('source') == 'new' and d.get('initialPrompt'):
    hook = 'SessionStart'
elif d.get('prompt') or d.get('userMessage'):
    hook = 'UserPromptSubmit'
elif d.get('error'):
    hook = 'errorOccurred'
elif tool and has_tool_result:
    hook = 'PostToolUse'
elif tool and not has_tool_result:
    hook = 'PreToolUse'
else:
    hook = 'unknown'

# Tool name mapping
tool_map = {
    'bash': 'Bash', 'shell': 'Bash', 'read_bash': 'Bash', 'run_command': 'Bash',
    'edit': 'Edit', 'multi_edit': 'MultiEdit', 'str_replace_editor': 'Edit',
    'apply_patch': 'Edit',
    'write': 'Write', 'create': 'Write', 'create_file': 'Write',
    'view': 'Read', 'read': 'Read', 'read_file': 'Read', 'list_directory': 'Read',
    'grep': 'Grep', 'search': 'Grep', 'rg': 'Grep',
    'glob': 'Glob', 'find_files': 'Glob', 'list_files': 'Glob',
    'agent': 'Agent', 'report_intent': 'Thinking', 'think': 'Thinking',
    'task_complete': 'Done', 'ask_user': 'Ask', 'exit_plan_mode': 'Planning',
    'web_search': 'WebSearch', 'web_fetch': 'WebFetch',
    'skill': 'Skill',
}
mapped_tool = tool_map.get(tool.lower(), tool) if tool else ''

# Build description
desc = ''
ti = tool_args
if tool.lower() in ('bash', 'shell', 'read_bash', 'run_command'):
    cmd = ti.get('command', '')
    if cmd: desc = cmd.split('&&')[0].split('|')[0].strip()[:80]
elif tool.lower() in ('edit', 'multi_edit', 'str_replace_editor'):
    fp = ti.get('file_path', ti.get('path', ''))
    desc = 'Editing ' + os.path.basename(fp) if fp else 'Editing'
elif tool.lower() in ('write', 'create', 'create_file'):
    fp = ti.get('file_path', ti.get('path', ''))
    desc = 'Writing ' + os.path.basename(fp) if fp else 'Writing'
elif tool.lower() in ('view', 'read', 'read_file', 'list_directory'):
    fp = ti.get('file_path', ti.get('path', ''))
    desc = 'Reading ' + os.path.basename(fp) if fp else 'Reading'
elif tool.lower() in ('grep', 'search', 'rg'):
    pat = ti.get('pattern', ti.get('query', ''))
    desc = 'Searching: ' + pat[:50] if pat else 'Searching'
elif tool.lower() in ('glob', 'find_files', 'list_files'):
    pat = ti.get('pattern', '')
    desc = 'Finding: ' + pat[:50] if pat else 'Finding files'
elif tool.lower() == 'apply_patch':
    # toolArgs is a string (patch content), not dict
    raw_args = d.get('toolArgs', '')
    if isinstance(raw_args, str):
        for line in raw_args.split('\n'):
            if line.startswith('*** Add File:'):
                desc = 'Creating ' + os.path.basename(line.split(':',1)[1].strip())
                break
            elif line.startswith('*** Update File:') or line.startswith('*** Modify File:'):
                desc = 'Editing ' + os.path.basename(line.split(':',1)[1].strip())
                break
        if not desc:
            desc = 'Applying patch'
    else:
        desc = 'Applying patch'
elif tool.lower() == 'report_intent':
    desc = ti.get('intent', ti.get('summary', ''))[:80] or 'Thinking'
elif tool.lower() == 'ask_user':
    desc = ti.get('question', '')[:80] or 'Waiting for input'
elif tool:
    desc = mapped_tool or tool

# Extract message from toolResult
last_message = ''
txt = tool_result.get('textResultForLlm', tool_result.get('text', ''))
if txt and isinstance(txt, str):
    lines = [l.strip() for l in txt.split('\n') if l.strip()]
    for line in lines:
        if len(line) > 10:
            last_message = line[:120]
            break
    if not last_message and lines:
        last_message = lines[0][:120]
if not last_message:
    last_message = desc

# Status
status = 'working'
if hook == 'Stop':
    # stopReason: "end_turn" = Copilot finished, waiting for user
    status = 'waitingForInput'
    stop_reason = d.get('stopReason', '')
    desc = 'Finished (' + stop_reason + ')' if stop_reason else 'Your turn'
    if not last_message:
        last_message = desc
elif hook == 'SessionEnd':
    # In Copilot CLI, reason:"complete" fires after EVERY turn, not just session close
    # Treat it as waitingForInput (same as Stop/end_turn)
    status = 'waitingForInput'
    desc = 'Your turn'
    if not last_message:
        last_message = desc
elif hook == 'SessionStart':
    status = 'working'
    prompt = d.get('initialPrompt', '')
    desc = 'Starting: ' + prompt[:60] if prompt else 'Session started'
    last_message = desc
elif hook == 'UserPromptSubmit':
    status = 'working'
    prompt = d.get('prompt', d.get('userMessage', ''))
    desc = 'User: ' + prompt[:60] if prompt else 'User sent prompt'
    last_message = desc
elif hook == 'errorOccurred':
    status = 'waitingForInput'
    err = d.get('error', '')
    if isinstance(err, dict): err = err.get('message', str(err))
    desc = 'Error: ' + str(err)[:60]
    last_message = desc
elif hook == 'PreToolUse':
    status = 'working'
    # Don't overwrite last_message for preToolUse, just update tool info
elif tool.lower() == 'ask_user':
    status = 'waitingForInput'
elif tool.lower() == 'report_intent':
    status = 'working'
    # Keep intent as desc but don't change status
elif tool.lower() == 'skill':
    # Skip skill tool — don't update UI for internal skill loading
    pass

# Secrets filter
for _pat in [r'(?:sk|pk|api|key|token|secret|password|bearer)[_-]?[A-Za-z0-9]{20,}', r'ghp_[A-Za-z0-9]{36}', r'eyJ[A-Za-z0-9_-]{20,}']:
    if re.search(_pat, last_message, re.IGNORECASE):
        last_message = '[redacted]'
        break

project = os.path.basename(cwd)

# Read previous data
tars_dir = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'tars-sessions')
os.makedirs(tars_dir, mode=0o700, exist_ok=True)
outpath = os.path.join(tars_dir, sid + '.json')
prev_data = {}
try:
    with open(outpath) as f:
        prev_data = json.load(f)
except: pass

# Skip PreToolUse — postToolUse will handle it with result
if hook == 'PreToolUse':
    sys.exit(0)

# Skip skill tool events — internal, not useful for UI
if tool.lower() == 'skill':
    sys.exit(0)

# Notification on Stop
if hook == 'Stop':
    notif = {'project': project, 'message': last_message or 'Your turn', 'type': 'waitingForInput', 'timestamp': int(time.time())}
    notif_path = os.path.join(tars_dir, '_notify_' + sid + '.json')
    tmpfd2, tmppath2 = tempfile.mkstemp(dir=tars_dir, suffix='.tmp')
    try:
        with os.fdopen(tmpfd2, 'w') as f2: json.dump(notif, f2)
        os.replace(tmppath2, notif_path)
    except:
        try: os.unlink(tmppath2)
        except: pass

out = {
    'session_id': sid,
    'project_name': project,
    'working_directory': cwd,
    'status': status,
    'tool_name': mapped_tool,
    'hook_event': hook,
    'tool_desc': desc,
    'last_message': last_message or desc or prev_data.get('last_message', ''),
    'updated_at': int(time.time()),
    'permission_mode': prev_data.get('permission_mode', ''),
    'agent_type': prev_data.get('agent_type', ''),
    'model': prev_data.get('model', ''),
    'active_agents': prev_data.get('active_agents', 0),
    'tool_history': prev_data.get('tool_history', []),
    'tool_count': prev_data.get('tool_count', 0),
}

# Try HTTP first
if urlopen:
    try:
        payload = json.dumps(out).encode()
        req = Request('http://127.0.0.1:7483/hook', data=payload, method='POST')
        req.add_header('Content-Type', 'application/json')
        urlopen(req, timeout=1)
    except: pass

# Always write file
tmpfd, tmppath = tempfile.mkstemp(dir=tars_dir, suffix='.tmp')
try:
    with os.fdopen(tmpfd, 'w') as f:
        json.dump(out, f, indent=2)
    os.replace(tmppath, outpath)
except:
    try: os.unlink(tmppath)
    except: pass
