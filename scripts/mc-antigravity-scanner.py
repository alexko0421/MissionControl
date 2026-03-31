#!/usr/bin/env python3
"""Antigravity scanner — simple, fast, real-time status detection.

Checks if Antigravity's agent log is actively being written to.
- Log growing right now → running
- Log stopped growing recently → done
- Log hasn't changed in a while → idle
"""

import json
import os
import glob
import hashlib
import subprocess
from datetime import datetime, timezone, timedelta

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
ANTIGRAVITY_LOGS = os.path.expanduser("~/Library/Application Support/Antigravity/logs")
SIZE_CACHE = os.path.join(STATUS_DIR, "ag-size-cache.json")


def is_antigravity_running():
    try:
        return subprocess.run(["pgrep", "-f", "Antigravity"],
            capture_output=True, timeout=3).returncode == 0
    except:
        return False


def get_agent_logs():
    """Find all active Antigravity agent logs."""
    log_dir = sorted(glob.glob(os.path.join(ANTIGRAVITY_LOGS, "*")))
    if not log_dir:
        return []
    latest = log_dir[-1]
    return glob.glob(os.path.join(latest, "window*", "exthost",
        "google.antigravity", "Antigravity.log"))


def load_size_cache():
    try:
        with open(SIZE_CACHE) as f:
            return json.load(f)
    except:
        return {}


def save_size_cache(cache):
    with open(SIZE_CACHE, "w") as f:
        json.dump(cache, f)


def get_workspace_from_log(log_file):
    """Quick scan for workspace path from last few cd commands."""
    try:
        with open(log_file, "r", errors="replace") as f:
            lines = f.readlines()[-30:]
        for line in reversed(lines):
            if "Command completed:" in line and "cd '" in line:
                s = line.index("cd '") + 4
                e = line.index("'", s)
                return line[s:e].strip()
    except:
        pass
    return None


def get_last_command(log_file, max_age_minutes=10):
    """Get the last meaningful terminal command from log, only if recent."""
    now = datetime.now()
    try:
        with open(log_file, "r", errors="replace") as f:
            lines = f.readlines()[-50:]
        for line in reversed(lines):
            if "[Terminal] Command completed:" in line:
                # Check timestamp of this line
                try:
                    ts = datetime.strptime(line[:23], "%Y-%m-%d %H:%M:%S.%f")
                    if (now - ts).total_seconds() > max_age_minutes * 60:
                        return None  # too old
                except:
                    pass
                try:
                    s = line.index("Command completed: ") + len("Command completed: ")
                    e = line.index(" exit code", s)
                    cmd = line[s:e].strip()
                    if cmd and not cmd.startswith("cd "):
                        return cmd[:60]
                except:
                    pass
    except:
        pass
    return None


def main():
    if not is_antigravity_running():
        # Antigravity not running — remove all AG entries
        if os.path.exists(STATUS_FILE):
            try:
                with open(STATUS_FILE) as f:
                    agents = json.load(f)
                agents = [a for a in agents if a.get("app") != "Antigravity"]
                with open(STATUS_FILE, "w") as f:
                    json.dump(agents, f, ensure_ascii=False, indent=2)
            except:
                pass
        return

    log_files = get_agent_logs()
    if not log_files:
        return

    size_cache = load_size_cache()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Check each log: is it growing?
    active_workspaces = {}

    for log_file in log_files:
        try:
            current_size = os.path.getsize(log_file)
            mtime = os.path.getmtime(log_file)
        except:
            continue

        prev_size = size_cache.get(log_file, 0)
        size_cache[log_file] = current_size

        age_seconds = datetime.now().timestamp() - mtime

        # Determine status
        if current_size > prev_size and age_seconds < 10:
            status = "running"  # actively writing right now
        elif age_seconds < 120:
            status = "running"  # wrote recently
        elif age_seconds < 600:
            status = "done"     # stopped within 10 min
        else:
            status = "idle"

        ws = get_workspace_from_log(log_file) or "Antigravity"
        ws_name = os.path.basename(ws)

        # Keep best (most active) status per workspace
        if ws not in active_workspaces or status == "running":
            active_workspaces[ws] = {
                "ws_name": ws_name,
                "status": status,
                "last_command": get_last_command(log_file),
            }

    save_size_cache(size_cache)

    # Update status.json
    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                agents = json.load(f)
        except:
            agents = []

    # Remove old Antigravity entries
    agents = [a for a in agents if a.get("app") != "Antigravity"]

    # Merge all workspaces into ONE entry — pick the most active
    if active_workspaces:
        best_ws = min(active_workspaces.keys(),
                      key=lambda w: ["running", "done", "idle"].index(active_workspaces[w]["status"])
                      if active_workspaces[w]["status"] in ["running", "done", "idle"] else 99)
        info = active_workspaces[best_ws]

        # Only show if agent is actually doing something (not idle)
        if info["status"] != "idle":
            last_cmd = info.get("last_command")
            if last_cmd:
                task = last_cmd
                summary = f"Workspace: {info['ws_name']}"
            else:
                task = f"{info['ws_name']} — agent active"
                summary = "Gemini agent"

            agents.append({
                "id": "ag-antigravity",
                "name": "Antigravity",
                "status": info["status"],
                "task": task,
                "summary": summary,
                "terminalLines": [],
                "nextAction": "",
                "updatedAt": now,
                "worktree": best_ws,
                "app": "Antigravity",
                "tmuxSession": None,
                "tmuxWindow": 0,
                "tmuxPane": 0,
            })

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
