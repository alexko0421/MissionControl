#!/usr/bin/env python3
"""Claude Code PostToolUse hook — marks agent back to 'running' after tool executes.

After the user approves a tool and it executes, set status back to 'running'.
"""

import json
import os
import sys
import hashlib
from datetime import datetime, timezone

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
os.makedirs(STATUS_DIR, exist_ok=True)

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

    agent_id = session_id[:8] if session_id else hashlib.md5(cwd.encode()).hexdigest()[:8]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                agents = json.load(f)
        except (json.JSONDecodeError, IOError):
            agents = []

    for i, a in enumerate(agents):
        if a["id"] == agent_id:
            agents[i]["status"] = "running"
            agents[i]["updatedAt"] = now
            break

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()
