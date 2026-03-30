#!/bin/zsh
# mc-update.sh — call this from your Claude Code sessions to update Mission Control
# Usage: mc-update.sh <agent-id> <status> <task> <summary> <next-action> [tmux-session] [tmux-window] [tmux-pane]
#
# Status values: running | blocked | done | idle

STATUS_DIR="$HOME/.mission-control"
STATUS_FILE="$STATUS_DIR/status.json"
mkdir -p "$STATUS_DIR"

ID="${1:-unknown}"
STATUS="${2:-running}"
TASK="${3:-進行中...}"
SUMMARY="${4:-}"
NEXT="${5:-}"
TMUX_SESSION="${6:-}"
TMUX_WINDOW="${7:-0}"
TMUX_PANE="${8:-0}"

python3 - "$ID" "$STATUS" "$TASK" "$SUMMARY" "$NEXT" "$TMUX_SESSION" "$TMUX_WINDOW" "$TMUX_PANE" "$STATUS_FILE" << 'PYEOF'
import json, sys, os
from datetime import datetime, timezone

agent_id = sys.argv[1]
status = sys.argv[2]
task = sys.argv[3]
summary = sys.argv[4]
next_action = sys.argv[5]
tmux_session = sys.argv[6] if sys.argv[6] else None
tmux_window = int(sys.argv[7])
tmux_pane = int(sys.argv[8])
status_file = sys.argv[9]

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# Load existing agents
agents = []
if os.path.exists(status_file):
    try:
        with open(status_file) as f:
            agents = json.load(f)
    except (json.JSONDecodeError, IOError):
        agents = []

# Remove existing entry for this agent
agents = [a for a in agents if a.get("id") != agent_id]

# Add new entry
agents.append({
    "id": agent_id,
    "name": agent_id,
    "status": status,
    "task": task,
    "summary": summary,
    "terminalLines": [],
    "nextAction": next_action,
    "updatedAt": now,
    "worktree": agent_id,
    "tmuxSession": tmux_session,
    "tmuxWindow": tmux_window,
    "tmuxPane": tmux_pane,
})

with open(status_file, "w") as f:
    json.dump(agents, f, ensure_ascii=False, indent=2)

print(f"✓ Mission Control updated: {agent_id} → {status}")
PYEOF
