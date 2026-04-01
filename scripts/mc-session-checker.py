#!/usr/bin/env python3
"""Session liveness checker — detects if Claude Code sessions are still running.

Checks every active agent (running/blocked) to see if the session is still alive.
Uses transcript file modification time as primary signal, falls back to process check.
If dead → removes from status.json immediately.

Works for Terminal, Conductor, and any app running Claude Code.
"""

import json
import os
import subprocess
from datetime import datetime, timezone

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")

# A session is considered alive if its transcript was modified within this window
TRANSCRIPT_ALIVE_SECS = 120  # 2 minutes


def get_active_claude_cwds():
    """Find all working directories where claude/node processes are active."""
    cwds = set()

    try:
        result = subprocess.run(
            ["pgrep", "-f", "claude"],
            capture_output=True, text=True, timeout=5
        )
        pids = result.stdout.strip().split("\n") if result.stdout.strip() else []

        for pid in pids:
            pid = pid.strip()
            if not pid:
                continue
            try:
                lsof = subprocess.run(
                    ["lsof", "-a", "-p", pid, "-d", "cwd", "-Fn"],
                    capture_output=True, text=True, timeout=3
                )
                for line in lsof.stdout.split("\n"):
                    if line.startswith("n/"):
                        cwds.add(line[1:])
            except:
                continue
    except:
        pass

    return cwds


def is_transcript_alive(transcript_path):
    """Check if a transcript file was recently modified."""
    if not transcript_path:
        return False
    try:
        mtime = os.path.getmtime(transcript_path)
        return (datetime.now().timestamp() - mtime) < TRANSCRIPT_ALIVE_SECS
    except:
        return False


def main():
    if not os.path.exists(STATUS_FILE):
        return

    try:
        with open(STATUS_FILE) as f:
            agents = json.load(f)
    except:
        return

    process_cwds = get_active_claude_cwds()

    dead_ids = []

    for agent in agents:
        if agent["status"] not in ("running", "blocked"):
            continue

        # Skip scanner-based agents — they have their own lifecycle
        app = agent.get("app", "")
        if app in ("Antigravity", "Codex"):
            continue

        # Primary check: transcript file still being written to
        transcript_path = agent.get("transcriptPath", "")
        if is_transcript_alive(transcript_path):
            continue

        # Fallback: check if a claude process is running in the agent's worktree
        worktree = agent.get("worktree", "")
        if worktree:
            wt = worktree.rstrip("/")
            is_alive = False
            for cwd in process_cwds:
                c = cwd.rstrip("/")
                if c == wt or c.startswith(wt + "/"):
                    is_alive = True
                    break
            if is_alive:
                continue

        dead_ids.append(agent["id"])

    if dead_ids:
        agents = [a for a in agents if a["id"] not in dead_ids]
        with open(STATUS_FILE, "w") as f:
            json.dump(agents, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
