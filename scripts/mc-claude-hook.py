#!/usr/bin/env python3
"""Claude Code Stop hook — reads Claude's last message from stdin and updates Mission Control.

No Gemini needed. Claude knows what it's doing — just ask it.

Usage in ~/.claude/settings.json:
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "python3 ~/Library/Mobile\\ Documents/com~apple~CloudDocs/MissionControl/scripts/mc-claude-hook.py"
      }]
    }]
  }
}
"""

import json
import os
import sys
import hashlib
from datetime import datetime, timezone

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
os.makedirs(STATUS_DIR, exist_ok=True)

def get_project_name(cwd):
    """Get a readable project name from the working directory."""
    if not cwd:
        return "Unknown"
    return os.path.basename(cwd)

def guess_status(message):
    """Simple heuristic for agent status based on message content."""
    msg = message.lower()
    # Blocked signals: asking questions, waiting for input
    blocked_signals = ["which option", "你想", "你觉得", "边个", "do you want", "should i",
                       "please choose", "waiting for", "need your", "要你决定", "需要你"]
    for signal in blocked_signals:
        if signal in msg:
            return "blocked"
    return "running"

def truncate(text, max_len):
    """Truncate text to max_len, adding ... if needed."""
    if len(text) <= max_len:
        return text
    return text[:max_len - 3] + "..."

def main():
    # Read hook input from stdin
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return
        hook_input = json.loads(raw)
    except (json.JSONDecodeError, IOError):
        return

    message = hook_input.get("last_assistant_message", "")
    cwd = hook_input.get("cwd", "")
    session_id = hook_input.get("session_id", "")

    if not message or not cwd:
        return

    project_name = get_project_name(cwd)
    agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    status = guess_status(message)

    # Extract first meaningful line as task (skip empty lines and short filler)
    lines = [l.strip() for l in message.split("\n") if l.strip() and len(l.strip()) > 5]
    task = truncate(lines[0], 60) if lines else "Working..."

    # Summary: first 3 meaningful lines
    summary = " ".join(lines[:3]) if lines else ""
    summary = truncate(summary, 300)

    # Next action: last meaningful line (often contains what to do next)
    next_action = truncate(lines[-1], 200) if lines else ""

    # Load existing agents
    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                agents = json.load(f)
        except (json.JSONDecodeError, IOError):
            agents = []

    # Update or add this agent
    found = False
    for i, a in enumerate(agents):
        if a["id"] == agent_id:
            agents[i].update({
                "name": project_name,
                "status": status,
                "task": task,
                "summary": summary,
                "nextAction": next_action,
                "updatedAt": now,
            })
            found = True
            break

    if not found:
        agents.append({
            "id": agent_id,
            "name": project_name,
            "status": status,
            "task": task,
            "summary": summary,
            "terminalLines": [],
            "nextAction": next_action,
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
