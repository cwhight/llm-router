#!/usr/bin/env python3
"""
Routing enforcement hook — warns when substantial code/prose is written
without a recent llm-router call. Fires synchronously on PostToolUse(Write|Edit)
so the warning is visible to the agent in its next context window.
"""
import json, sys, os, time, datetime

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool_name = data.get('tool_name', '')
tool_input = data.get('tool_input', {})

if tool_name not in ('Edit', 'Write'):
    sys.exit(0)

file_path = tool_input.get('file_path', '')
ext = os.path.splitext(file_path)[1].lower()

if ext not in ('.go', '.ts', '.tsx', '.js', '.jsx', '.py', '.md', '.sql'):
    sys.exit(0)

content = tool_input.get('content', '') or tool_input.get('new_string', '')
lines = len([l for l in content.splitlines() if l.strip()])

if lines < 20:
    sys.exit(0)

fname = os.path.basename(file_path)
routing_log = os.path.expanduser('~/.config/llm-router/routing.log')

if not os.path.exists(routing_log):
    print(f'[llm-router-hook] ⚠  {fname} ({lines} lines) — no routing log. Use llm-router for substantial writes.', flush=True)
    sys.exit(0)

last_line = ''
try:
    with open(routing_log) as f:
        for line in f:
            if line.strip():
                last_line = line.strip()
except Exception:
    sys.exit(0)

if not last_line:
    print(f'[llm-router-hook] ⚠  {fname} ({lines} lines) — routing log empty. Use llm-router.', flush=True)
    sys.exit(0)

try:
    ts_str = ' '.join(last_line.split()[:2])
    last_ts = datetime.datetime.strptime(ts_str, '%Y-%m-%d %H:%M:%S').timestamp()
    age = int(time.time() - last_ts)
    if age > 120:
        print(f'[llm-router-hook] ⚠  {fname} ({lines} lines) — last llm-router call was {age}s ago. Route this through llm-router before writing.', flush=True)
    else:
        print(f'[llm-router-hook] ✓  {fname} ({lines} lines) — routed {age}s ago via ollama', flush=True)
except Exception:
    pass
