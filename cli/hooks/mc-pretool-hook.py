#!/usr/bin/env python3
"""Claude Code PreToolUse hook — sends permission request via mc-bridge (blocking)."""

import json, os, sys, hashlib, subprocess, uuid

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
    request_id = f"req_{uuid.uuid4().hex[:12]}"
    tool_name = hook_input.get("tool_name", "Unknown")
    tool_input = hook_input.get("tool_input", {})

    display_input = {}
    if isinstance(tool_input, dict):
        if "command" in tool_input: display_input["command"] = str(tool_input["command"])[:500]
        if "file_path" in tool_input: display_input["file_path"] = str(tool_input["file_path"])
        if "description" in tool_input: display_input["description"] = str(tool_input["description"])[:200]
        if not display_input:
            for k, v in list(tool_input.items())[:2]:
                display_input[k] = str(v)[:200]

    cmd = [sys.executable, BRIDGE, "permission",
        "--agent-id", agent_id, "--request-id", request_id,
        "--tool", tool_name, "--tool-input", json.dumps(display_input)]

    try:
        result = subprocess.run(cmd, timeout=15, capture_output=True, text=True)
        if result.stdout.strip():
            print(result.stdout.strip())
    except subprocess.TimeoutExpired:
        pass

if __name__ == "__main__":
    main()
