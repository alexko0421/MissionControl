#!/bin/zsh
# mc-scan.sh — Scan running Claude Code sessions, summarize with Gemini, update Mission Control
# Usage: mc-scan.sh
# Requires: GEMINI_API_KEY environment variable

STATUS_DIR="$HOME/.mission-control"
STATUS_FILE="$STATUS_DIR/status.json"
mkdir -p "$STATUS_DIR"

API_KEY="${GEMINI_API_KEY:-}"
if [ -z "$API_KEY" ]; then
    echo "✗ GEMINI_API_KEY not set"
    exit 1
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Find Claude Code working directories from running processes
CWDS=$(lsof -c claude 2>/dev/null | grep cwd | awk '{print $NF}' | sort -u || true)

if [ -z "$CWDS" ]; then
    echo "✓ No Claude sessions found"
    exit 0
fi

AGENTS="[]"

while IFS= read -r CWD; do
    [ -z "$CWD" ] && continue
    SESSION_NAME=$(basename "$CWD")

    # Gather git context
    GIT_INFO="Directory: $CWD"
    if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
        BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "unknown")
        LOG=$(git -C "$CWD" log --oneline -5 2>/dev/null || echo "no commits")
        CHANGED=$(git -C "$CWD" status --short 2>/dev/null | head -10 || echo "")
        GIT_INFO="Branch: ${BRANCH}\nRecent commits:\n${LOG}\nChanged files:\n${CHANGED}"
    fi

    # Call Gemini
    PROMPT_TEXT="根據以下 git 資訊，用繁體中文回覆 JSON。不要加 markdown code block。格式：{\"task\": \"一句話描述（最多20字）\", \"summary\": \"2-3句摘要\", \"nextAction\": \"下一步建議\"}\n\n${GIT_INFO}"

    ESCAPED_PROMPT=$(python3 -c "import json; print(json.dumps('''${PROMPT_TEXT}'''))")

    RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${API_KEY}" \
        -H 'Content-Type: application/json' \
        -d "{\"contents\":[{\"parts\":[{\"text\":${ESCAPED_PROMPT}}]}],\"generationConfig\":{\"temperature\":0.1,\"maxOutputTokens\":300}}" \
        2>/dev/null || echo "{}")

    # Parse response
    PARSED=$(python3 << 'PYEOF'
import json, sys, re
try:
    data = json.loads("""${RESPONSE}""")
except:
    try:
        data = json.loads(sys.stdin.read()) if False else None
    except:
        data = None

# Try to read from the curl response
import subprocess
response_text = """${RESPONSE}"""
try:
    data = json.loads(response_text)
    text = data['candidates'][0]['content']['parts'][0]['text']
    text = re.sub(r'```json?\s*', '', text)
    text = re.sub(r'```', '', text)
    parsed = json.loads(text.strip())
    print(json.dumps(parsed, ensure_ascii=False))
except:
    print('{"task":"開發中...","summary":"正在進行開發工作","nextAction":"繼續開發"}')
PYEOF
    )

    TASK=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('task','開發中...'))")
    SUMMARY_TEXT=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('summary',''))")
    NEXT=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('nextAction',''))")

    AGENT_ID=$(echo "$CWD" | md5)

    # Build agent JSON
    AGENTS=$(python3 << PYEOF
import json
agents = json.loads('''${AGENTS}''')
agents.append({
    "id": "${AGENT_ID}",
    "name": "${SESSION_NAME}",
    "status": "running",
    "task": json.loads($(echo "$TASK" | python3 -c "import sys,json; print(json.dumps(json.dumps(sys.stdin.read().strip())))")),
    "summary": json.loads($(echo "$SUMMARY_TEXT" | python3 -c "import sys,json; print(json.dumps(json.dumps(sys.stdin.read().strip())))")),
    "terminalLines": [],
    "nextAction": json.loads($(echo "$NEXT" | python3 -c "import sys,json; print(json.dumps(json.dumps(sys.stdin.read().strip())))")),
    "updatedAt": "${NOW}",
    "worktree": "${CWD}",
    "tmuxSession": None,
    "tmuxWindow": 0,
    "tmuxPane": 0,
})
print(json.dumps(agents, ensure_ascii=False, indent=2))
PYEOF
    )

    echo "  ✓ ${SESSION_NAME}: ${TASK}"
done <<< "$CWDS"

echo "$AGENTS" > "$STATUS_FILE"
echo "✓ Mission Control updated"
