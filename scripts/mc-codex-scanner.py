#!/usr/bin/env python3
"""Codex scanner — reads Codex's SQLite database to detect active sessions.

Only shows sessions with REAL recent activity. Extracts actual task content.
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

    # Get sessions active in last 24 hours (always show, status reflects recency)
    now_ts = int(datetime.now().timestamp())
    cutoff = now_ts - 86400  # 24 hours

    try:
        rows = db.execute(
            "SELECT id, title, cwd, source, updated_at, model, first_user_message "
            "FROM threads "
            "WHERE updated_at > ? AND (archived IS NULL OR archived = 0) "
            "ORDER BY updated_at DESC LIMIT 10",
            (cutoff,)
        ).fetchall()
    except:
        db.close()
        return

    db.close()

    # Load existing agents
    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                agents = json.load(f)
        except:
            agents = []

    # Remove old Codex entries first (re-add active ones)
    agents = [a for a in agents if a.get("app") != "Codex"]

    if not rows:
        # No active sessions — just write back without Codex entries
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location("mc_cleanup",
                os.path.join(os.path.dirname(os.path.abspath(__file__)), "mc-cleanup.py"))
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            agents = mod.cleanup_agents(agents)
        except:
            pass
        with open(STATUS_FILE, "w") as f:
            json.dump(agents, f, ensure_ascii=False, indent=2)
        return

    for row in rows:
        thread_id, title, cwd, source, updated_at, model, first_msg = row

        agent_id = "cx-" + hashlib.md5(thread_id.encode()).hexdigest()[:6]
        age = now_ts - updated_at
        ws_name = os.path.basename(cwd) if cwd else "Codex"

        # Determine status based on recency
        if age < 120:       # 2 minutes
            status = "running"
        elif age < 600:     # 10 minutes
            status = "done"
        else:
            status = "idle"

        # Build task from actual content
        task = ""
        if title and title.strip():
            task = title.strip()[:60]
        elif first_msg and first_msg.strip():
            task = first_msg.strip()[:60]
        else:
            task = "Working..."

        # Build summary
        summary_parts = []
        if model:
            summary_parts.append(f"Model: {model}")
        if source:
            summary_parts.append(f"Source: {source}")
        summary = " | ".join(summary_parts)

        updated_str = datetime.fromtimestamp(updated_at, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        agents.append({
            "id": agent_id,
            "name": f"Codex ({ws_name})",
            "status": status,
            "task": task,
            "summary": summary,
            "terminalLines": [],
            "nextAction": "",
            "updatedAt": updated_str,
            "worktree": cwd,
            "app": "Codex",
            "tmuxSession": None,
            "tmuxWindow": 0,
            "tmuxPane": 0,
        })

    # Cleanup
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("mc_cleanup",
            os.path.join(os.path.dirname(os.path.abspath(__file__)), "mc-cleanup.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        agents = mod.cleanup_agents(agents)
    except:
        pass

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
