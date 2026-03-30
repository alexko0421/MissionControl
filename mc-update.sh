#!/bin/zsh
# mc-update.sh — call this from your Claude Code sessions to update Mission Control
# Usage: mc-update.sh <agent-id> <status> <task> <summary> <next-action> [tmux-session] [tmux-window] [tmux-pane]
#
# Example:
#   mc-update.sh "asami-voice" "running" "重構 session handler" "完成了X" "下一步做Y" "conductor" 0 0
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
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read existing entries (excluding this agent)
EXISTING="[]"
if [ -f "$STATUS_FILE" ]; then
    EXISTING=$(python3 -c "
import json, sys
try:
    data = json.load(open('$STATUS_FILE'))
    filtered = [a for a in data if a.get('id') != '$ID']
    print(json.dumps(filtered))
except:
    print('[]')
")
fi

# Build new entry
NEW_ENTRY=$(python3 -c "
import json
entry = {
    'id': '$ID',
    'name': '$ID',
    'status': '$STATUS',
    'task': '$TASK',
    'summary': '$SUMMARY',
    'terminalLines': [],
    'nextAction': '$NEXT',
    'updatedAt': '$NOW',
    'worktree': '$ID',
    'tmuxSession': '$TMUX_SESSION' if '$TMUX_SESSION' else None,
    'tmuxWindow': int('$TMUX_WINDOW'),
    'tmuxPane': int('$TMUX_PANE'),
}
existing = json.loads('$EXISTING'.replace(\"'\", '\"') if False else '''$EXISTING''')
existing.append(entry)
print(json.dumps(existing, ensure_ascii=False, indent=2))
")

echo "$NEW_ENTRY" > "$STATUS_FILE"
echo "✓ Mission Control updated: $ID → $STATUS"
