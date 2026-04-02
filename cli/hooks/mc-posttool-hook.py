#!/usr/bin/env python3
"""Claude Code PostToolUse hook — marks agent back to 'running' via mc-bridge."""

import json, os, sys, hashlib, subprocess

BRIDGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mc-bridge.py")

def main():
    try:
        raw = sys.stdin.read()
        if not raw.strip(): return
        hook_input = json.loads(raw)
    except (json.JSONDecodeError, IOError): return

    cwd = hook_input.get("cwd", "")
    if not cwd: return

    agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]
    subprocess.run([sys.executable, BRIDGE, "status",
        "--agent-id", agent_id, "--status", "running"], timeout=5, capture_output=True)

if __name__ == "__main__":
    main()
