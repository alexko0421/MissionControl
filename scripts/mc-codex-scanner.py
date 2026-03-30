#!/usr/bin/env python3
"""Codex scanner — reads Codex's SQLite database to detect agent sessions
and writes status to ~/.mission-control/status.json.
"""

import json
import os
import sqlite3
import hashlib
from datetime import datetime, timezone, timedelta

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
CODEX_DB = os.path.expanduser("~/.codex/state_5.sqlite")
os.makedirs(STATUS_DIR, exist_ok=True)


def main():
    if not os.path.exists(CODEX_DB):
        return

    try:
        db = sqlite3.connect(CODEX_DB, timeout=3)
        db.execute("PRAGMA journal_mode=WAL")
    except:
        return

    # Get recent threads (updated in last 24 hours)
    cutoff = int((datetime.now() - timedelta(hours=24)).timestamp())
    try:
        rows = db.execute(
            "SELECT id, title, cwd, source, updated_at, model, archived FROM threads "
            "WHERE updated_at > ? AND (archived IS NULL OR archived = 0) "
            "ORDER BY updated_at DESC LIMIT 10",
            (cutoff,)
        ).fetchall()
    except:
        db.close()
        return

    if not rows:
        db.close()
        return

    # Check for active sessions by looking at recent rollout files
    now = datetime.now(timezone.utc)
    now_ts = int(now.timestamp())

    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                agents = json.load(f)
        except:
            agents = []

    updated = False
    for row in rows:
        thread_id, title, cwd, source, updated_at, model, archived = row

        agent_id = "cx-" + hashlib.md5(thread_id.encode()).hexdigest()[:6]
        age = now_ts - updated_at
        ws_name = os.path.basename(cwd) if cwd else "Codex"

        # Determine status based on age
        if age < 120:  # Active in last 2 minutes
            status = "running"
        elif age < 600:  # Active in last 10 minutes
            status = "idle"
        else:
            status = "done"

        task = (title or "Working...")[:60]
        now_str = datetime.fromtimestamp(updated_at, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        # Find existing entry
        found = False
        for i, a in enumerate(agents):
            if a["id"] == agent_id:
                if a.get("status") != status or a.get("task") != task:
                    agents[i].update({
                        "status": status,
                        "task": task,
                        "updatedAt": now_str,
                        "app": "Codex",
                    })
                    updated = True
                found = True
                break

        if not found:
            agents.append({
                "id": agent_id,
                "name": f"Codex ({ws_name})",
                "status": status,
                "task": task,
                "summary": f"Model: {model or 'unknown'}",
                "terminalLines": [],
                "nextAction": "",
                "updatedAt": now_str,
                "worktree": cwd,
                "app": "Codex",
                "tmuxSession": None,
                "tmuxWindow": 0,
                "tmuxPane": 0,
            })
            updated = True

    db.close()

    if updated:
        with open(STATUS_FILE, "w") as f:
            json.dump(agents, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
