#!/usr/bin/env python3
"""Antigravity log scanner — polls Antigravity's logs to detect agent activity
and writes status to ~/.mission-control/status.json.

Designed to be called periodically (e.g. every 3-5 seconds) from MissionControl's polling loop.
"""

import json
import os
import glob
import hashlib
from datetime import datetime, timezone, timedelta

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
ANTIGRAVITY_LOGS = os.path.expanduser("~/Library/Application Support/Antigravity/logs")
os.makedirs(STATUS_DIR, exist_ok=True)

# Cache last scan position per log file
SCAN_STATE_FILE = os.path.join(STATUS_DIR, "antigravity-scan-state.json")


def get_latest_log_dir():
    """Find the most recent Antigravity log directory."""
    dirs = sorted(glob.glob(os.path.join(ANTIGRAVITY_LOGS, "*")))
    return dirs[-1] if dirs else None


def get_agent_log(log_dir):
    """Find the Antigravity agent log file."""
    # Check for the main agent log
    candidates = [
        os.path.join(log_dir, "window1", "exthost", "google.antigravity", "Antigravity.log"),
    ]
    # Also check for multiple windows
    for i in range(1, 5):
        candidates.append(
            os.path.join(log_dir, f"window{i}", "exthost", "google.antigravity", "Antigravity.log")
        )
    return [c for c in candidates if os.path.exists(c)]


def load_scan_state():
    """Load previous scan positions."""
    if os.path.exists(SCAN_STATE_FILE):
        try:
            with open(SCAN_STATE_FILE) as f:
                return json.load(f)
        except:
            pass
    return {}


def save_scan_state(state):
    """Save scan positions."""
    with open(SCAN_STATE_FILE, "w") as f:
        json.dump(state, f)


def parse_log_tail(log_file, last_pos=0):
    """Read new lines from log file since last position."""
    try:
        size = os.path.getsize(log_file)
        if size <= last_pos:
            return [], last_pos
        with open(log_file, "r", errors="replace") as f:
            f.seek(max(0, last_pos))
            lines = f.readlines()
        return lines, size
    except:
        return [], last_pos


def detect_workspace(lines):
    """Detect which workspace Antigravity is working in from log lines."""
    workspace = None
    for line in reversed(lines):
        # Look for cd commands or file paths
        if "Command completed:" in line and "cd " in line:
            # Extract path from cd command
            try:
                idx = line.index("cd '") + 4 if "cd '" in line else line.index("cd ") + 3
                end = line.index("'", idx) if "cd '" in line else line.index(" exit", idx)
                path = line[idx:end].strip()
                if path and path != "/":
                    workspace = path
            except:
                pass
    return workspace


def detect_status(lines):
    """Detect agent status from recent log lines.

    Returns: (status, task_hint)
    """
    if not lines:
        return "idle", None

    recent = lines[-30:]  # Look at last 30 lines

    has_planner = False
    has_terminal_cmd = False
    has_error = False
    last_cmd = None
    last_activity_time = None
    is_stopped = False

    for line in recent:
        if "planner_generator" in line:
            has_planner = True
        if "[Terminal] Command completed:" in line:
            has_terminal_cmd = True
            try:
                cmd_start = line.index("Command completed: ") + len("Command completed: ")
                cmd_end = line.index(" exit code", cmd_start)
                last_cmd = line[cmd_start:cmd_end].strip()
            except:
                pass
        if "executor is not currently running" in line:
            is_stopped = True
        if "non-terminal status: CORTEX_STEP_STATUS_RUNNING" in line:
            has_planner = True
        if "Error" in line or "error" in line:
            has_error = True

        # Extract timestamp
        if line.startswith("2026-"):
            try:
                ts_str = line[:23]
                last_activity_time = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S.%f")
            except:
                pass

    # Determine status based on ALL lines (not just new ones)
    if is_stopped and not has_planner:
        return "done", last_cmd
    if has_planner or has_terminal_cmd:
        # Check if activity is recent
        if last_activity_time:
            age = datetime.now() - last_activity_time
            if age > timedelta(minutes=5):
                return "idle", last_cmd
        return "running", last_cmd

    return "idle", None


def update_status_file(agent_id, name, status, task, workspace):
    """Update or add agent entry in status.json."""
    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                agents = json.load(f)
        except:
            agents = []

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    found = False
    for i, a in enumerate(agents):
        if a["id"] == agent_id:
            # Only update if status changed or task changed
            if a.get("status") != status or a.get("task") != task:
                agents[i].update({
                    "status": status,
                    "task": task or agents[i].get("task", ""),
                    "updatedAt": now,
                    "app": "Antigravity",
                })
            found = True
            break

    if not found:
        agents.append({
            "id": agent_id,
            "name": name,
            "status": status,
            "task": task or "Working...",
            "summary": "",
            "terminalLines": [],
            "nextAction": "",
            "updatedAt": now,
            "worktree": workspace,
            "app": "Antigravity",
            "tmuxSession": None,
            "tmuxWindow": 0,
            "tmuxPane": 0,
        })

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)


def main():
    log_dir = get_latest_log_dir()
    if not log_dir:
        return

    log_files = get_agent_log(log_dir)
    if not log_files:
        return

    scan_state = load_scan_state()

    for log_file in log_files:
        last_pos = scan_state.get(log_file, 0)
        # First scan: read last 100 lines for initial state
        if last_pos == 0:
            try:
                with open(log_file, "r", errors="replace") as f:
                    all_lines = f.readlines()
                lines = all_lines[-100:] if len(all_lines) > 100 else all_lines
                new_pos = os.path.getsize(log_file)
            except:
                lines, new_pos = [], 0
        else:
            lines, new_pos = parse_log_tail(log_file, last_pos)
        scan_state[log_file] = new_pos

        if not lines:
            continue

        # Detect workspace and status
        workspace = detect_workspace(lines) or "Antigravity"
        status, task_hint = detect_status(lines)

        # Generate agent ID from workspace path
        ws_name = os.path.basename(workspace) if workspace != "Antigravity" else "Antigravity"
        agent_id = "ag-" + hashlib.md5(log_file.encode()).hexdigest()[:6]

        # Build task description
        if task_hint:
            task = task_hint[:60]
        elif status == "running":
            task = "Agent working..."
        elif status == "done":
            task = "Task completed"
        else:
            task = "Idle"

        update_status_file(agent_id, f"Antigravity ({ws_name})", status, task, workspace)

    save_scan_state(scan_state)


if __name__ == "__main__":
    main()
