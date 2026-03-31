#!/usr/bin/env python3
"""Shared cleanup logic for Mission Control status.json.

Import and call cleanup_agents(agents) before writing status.json.
Can also be run standalone to clean up immediately.
"""

import json
import os
from datetime import datetime, timezone, timedelta

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")


def cleanup_agents(agents):
    """Clean up stale and duplicate agents. Returns cleaned list."""
    now = datetime.now(timezone.utc)

    # 1a. Deduplicate by id (keep most recent)
    seen = {}
    for a in agents:
        aid = a["id"]
        if aid in seen:
            existing_time = seen[aid].get("updatedAt", "")
            new_time = a.get("updatedAt", "")
            if new_time > existing_time:
                seen[aid] = a
        else:
            seen[aid] = a
    agents = list(seen.values())

    # 1b. Deduplicate by name (keep most recent)
    seen_names = {}
    for a in agents:
        name = a["name"]
        if name in seen_names:
            existing_time = seen_names[name].get("updatedAt", "")
            new_time = a.get("updatedAt", "")
            if new_time > existing_time:
                seen_names[name] = a
        else:
            seen_names[name] = a
    agents = list(seen_names.values())

    # 2. Auto-downgrade stale statuses
    for a in agents:
        try:
            updated = datetime.fromisoformat(a["updatedAt"].replace("Z", "+00:00"))
            age = now - updated
        except:
            age = timedelta(hours=99)

        # done for over 10 minutes → idle
        if a["status"] == "done" and age > timedelta(minutes=10):
            a["status"] = "idle"

        # running/blocked for over 1 hour → idle
        if a["status"] in ("running", "blocked") and age > timedelta(hours=1):
            a["status"] = "idle"

    # 3. Remove very old entries
    cleaned = []
    for a in agents:
        try:
            updated = datetime.fromisoformat(a["updatedAt"].replace("Z", "+00:00"))
            age = now - updated
        except:
            age = timedelta(hours=99)

        # idle > 2 hours → remove (but keep scanner-based apps, they manage their own lifecycle)
        if a["status"] == "idle" and age > timedelta(hours=2):
            if a.get("app") not in ("Antigravity", "Codex"):
                continue

        cleaned.append(a)

    return cleaned


def main():
    """Run standalone cleanup."""
    if not os.path.exists(STATUS_FILE):
        return

    try:
        with open(STATUS_FILE) as f:
            agents = json.load(f)
    except:
        return

    before = len(agents)
    agents = cleanup_agents(agents)
    after = len(agents)

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)

    if before != after:
        print(f"Cleaned: {before} → {after} agents")


if __name__ == "__main__":
    main()
