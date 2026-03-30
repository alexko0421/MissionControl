#!/usr/bin/env python3
"""Claude Code UserPromptSubmit hook — immediately marks agent as 'running' when user sends a message.

This makes Mission Control update in real-time: the moment you hit Enter,
the status changes from blocked/done to running.
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
    if not cwd:
        return

    agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Load existing agents
    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                agents = json.load(f)
        except (json.JSONDecodeError, IOError):
            agents = []

    # Find and update this agent to running
    for i, a in enumerate(agents):
        if a["id"] == agent_id:
            agents[i]["status"] = "running"
            agents[i]["updatedAt"] = now
            break
    else:
        # Agent not found yet — create a minimal entry
        agents.append({
            "id": agent_id,
            "name": os.path.basename(cwd),
            "status": "running",
            "task": "處理中...",
            "summary": "",
            "terminalLines": [],
            "nextAction": "",
            "updatedAt": now,
            "worktree": cwd,
            "tmuxSession": None,
            "tmuxWindow": 0,
            "tmuxPane": 0,
        })

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()
