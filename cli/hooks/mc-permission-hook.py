#!/usr/bin/env python3
"""Claude Code PermissionRequest hook — delegates approvals to MissionControl."""

import json
import os
import sys
import hashlib
import subprocess
import uuid

BRIDGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mc-bridge.py")


def main():
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return
        hook_input = json.loads(raw)
    except (json.JSONDecodeError, IOError):
        return

    cwd = hook_input.get("cwd", "")
    session_id = hook_input.get("session_id", "")
    if not cwd:
        return

    tool_name = hook_input.get("tool_name", "Unknown")
    tool_input = hook_input.get("tool_input", {})
    if not isinstance(tool_input, dict):
        tool_input = {"command": str(tool_input)}

    agent_id = session_id[:8] if session_id else hashlib.md5(cwd.encode()).hexdigest()[:8]
    request_id = f"perm_{uuid.uuid4().hex[:12]}"

    cmd = [
        sys.executable,
        BRIDGE,
        "permission",
        "--agent-id",
        agent_id,
        "--request-id",
        request_id,
        "--tool",
        tool_name,
        "--tool-input",
        json.dumps(tool_input, ensure_ascii=False),
    ]

    try:
        result = subprocess.run(cmd, timeout=300, capture_output=True, text=True)
        if result.stdout.strip():
            print(result.stdout.strip())
        else:
            print(json.dumps({"approve": True}))
    except subprocess.TimeoutExpired:
        print(json.dumps({"approve": True}))


if __name__ == "__main__":
    main()
