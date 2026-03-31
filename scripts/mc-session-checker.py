#!/usr/bin/env python3
"""Session liveness checker — detects if Claude Code sessions are still running.

Checks every active agent (running/blocked) to see if there's still a process
working in that directory. If not → marks as 'done'.

Works for Terminal, Conductor, and any app running Claude Code.
"""

import json
import os
import subprocess
from datetime import datetime, timezone

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")


def get_active_claude_cwds():
    """Find all working directories where claude/node processes are active."""
    cwds = set()

    try:
        # Find all claude-related process PIDs
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
                # Get cwd for this PID via lsof
                lsof = subprocess.run(
                    ["lsof", "-a", "-p", pid, "-d", "cwd", "-Fn"],
                    capture_output=True, text=True, timeout=3
                )
                for line in lsof.stdout.split("\n"):
                    if line.startswith("n/"):
                        cwds.add(line[1:])  # strip the 'n' prefix
            except:
                continue
    except:
        pass

    return cwds


def check_claude_sessions_dir():
    """Check ~/.claude/projects/ for recently active sessions.
    Returns set of working directories with active sessions."""
    active_cwds = set()
    projects_dir = os.path.expanduser("~/.claude/projects")
    if not os.path.exists(projects_dir):
        return active_cwds

    now = datetime.now().timestamp()
    for entry in os.listdir(projects_dir):
        project_path = os.path.join(projects_dir, entry)
        if not os.path.isdir(project_path):
            continue

        # Check for recent JSONL files (active sessions)
        for fname in os.listdir(project_path):
            if fname.endswith(".jsonl"):
                fpath = os.path.join(project_path, fname)
                try:
                    mtime = os.path.getmtime(fpath)
                    # Active if modified in last 2 minutes
                    if now - mtime < 120:
                        # Decode directory name back to path
                        # e.g. "-Users-kochunlong-conductor-workspaces-..." → "/Users/kochunlong/conductor/workspaces/..."
                        cwd = "/" + entry.lstrip("-").replace("-", "/")
                        active_cwds.add(cwd)
                except:
                    continue

    return active_cwds


def main():
    if not os.path.exists(STATUS_FILE):
        return

    try:
        with open(STATUS_FILE) as f:
            agents = json.load(f)
    except:
        return

    # Get all active working directories
    process_cwds = get_active_claude_cwds()
    session_cwds = check_claude_sessions_dir()
    all_active_cwds = process_cwds | session_cwds

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    updated = False

    for i, agent in enumerate(agents):
        # Only check running/blocked agents (not done/idle)
        if agent["status"] not in ("running", "blocked"):
            continue

        # Skip scanner-based agents (Antigravity, Codex) — they have their own lifecycle
        app = agent.get("app", "")
        if app in ("Antigravity", "Codex"):
            continue

        worktree = agent.get("worktree", "")
        if not worktree:
            continue

        # Check if any active cwd matches this agent's worktree
        is_alive = False
        for cwd in all_active_cwds:
            # Match if cwd starts with worktree or worktree starts with cwd
            if cwd.startswith(worktree) or worktree.startswith(cwd):
                is_alive = True
                break

        if not is_alive:
            agents[i]["status"] = "done"
            agents[i]["updatedAt"] = now
            updated = True

    if updated:
        with open(STATUS_FILE, "w") as f:
            json.dump(agents, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
