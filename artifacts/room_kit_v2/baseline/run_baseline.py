"""Execution-only baseline probe. No asset or project edits."""
from pathlib import Path
import json
import os
import re
import secrets
import socket
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
GODOT = '/opt/homebrew/bin/godot'
# The editor plugin requires an auth token even for a short import process.
# Fresh process-local token, ephemeral loopback port; never save token bytes.
env = os.environ.copy()
env['GODOT_MCP_TOKEN'] = secrets.token_hex(32)
with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0))
    env['GODOT_MCP_PORT'] = str(sock.getsockname()[1])
commands = [('import-authenticated', ['--editor', '--quit'], '')]
for script, marker in [
    ('additional_dressing_procgen_smoke', 'ADDITIONAL DRESSING PROCGEN PASS'),
    ('prop_visual_binding_smoke', 'PROP VISUAL BINDING'),
    ('gameplay_prop_imported_visual_smoke', 'GAMEPLAY PROP IMPORTED VISUAL'),
    ('builder_placed_props_smoke', 'BUILDER PLACED PROPS'),
    ('start_scenario_smoke', 'START SCENARIO'),
]:
    commands.append((script, ['--script', 'scripts/validation/'+script+'.gd'], marker))
results = []
for label, extra, marker in commands:
    command = [GODOT, '--headless', '--path', str(ROOT), '--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3'] + extra
    try:
        run = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
        text, code = run.stdout, run.returncode
    except subprocess.TimeoutExpired as exc:
        text = exc.stdout or b''
        if isinstance(text, bytes):
            text = text.decode(errors='replace')
        code = 124
        text += '\nBASELINE_TIMEOUT\n'
    (OUT/(label+'.log')).write_text(text)
    diagnostics = [line for line in text.splitlines() if re.search(r'(ERROR:|WARNING:|SCRIPT ERROR:)', line)]
    results.append({'label':label,'command':command,'exit':code,'marker_seen': not marker or marker in text,'diagnostics':diagnostics,'log':str(OUT/(label+'.log'))})
    (OUT/'godot-results.json').write_text(json.dumps(results,indent=2))
    print(json.dumps(results[-1]), flush=True)
print('BASELINE_PROBES_FINISHED', len(results))
