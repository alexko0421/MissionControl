#!/usr/bin/env python3
"""Claude Code Stop hook — reads Claude's last message from stdin and updates Mission Control.

No Gemini needed. Claude knows what it's doing — just ask it.

Usage in ~/.claude/settings.json:
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "python3 ~/Library/Mobile\\ Documents/com~apple~CloudDocs/MissionControl/scripts/mc-claude-hook.py"
      }]
    }]
  }
}
"""

import json
import os
import sys
import re
import hashlib
import subprocess
from datetime import datetime, timezone
from urllib.request import Request, urlopen

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
os.makedirs(STATUS_DIR, exist_ok=True)

# Gemini API key for summarization
API_KEY = os.environ.get("GEMINI_API_KEY", "")
if not API_KEY:
    key_file = os.path.join(STATUS_DIR, "gemini-key.txt")
    if os.path.exists(key_file):
        API_KEY = open(key_file).read().strip()

def get_project_name(cwd):
    """Get a readable project name from the working directory."""
    if not cwd:
        return "Unknown"
    return os.path.basename(cwd)

def detect_tmux():
    """Detect if we're running inside tmux and return session/window/pane."""
    if not os.environ.get("TMUX"):
        return None, 0, 0
    try:
        session = subprocess.check_output(
            ["tmux", "display-message", "-p", "#{session_name}"],
            stderr=subprocess.DEVNULL, timeout=3
        ).decode().strip()
        window = subprocess.check_output(
            ["tmux", "display-message", "-p", "#{window_index}"],
            stderr=subprocess.DEVNULL, timeout=3
        ).decode().strip()
        pane = subprocess.check_output(
            ["tmux", "display-message", "-p", "#{pane_index}"],
            stderr=subprocess.DEVNULL, timeout=3
        ).decode().strip()
        return session or None, int(window or 0), int(pane or 0)
    except:
        return None, 0, 0

def guess_status(message):
    """Simple heuristic for agent status based on message content."""
    msg = message.lower()
    # Blocked signals: asking questions, waiting for input
    blocked_signals = ["which option", "你想", "你觉得", "边个", "do you want", "should i",
                       "please choose", "waiting for", "need your", "要你决定", "需要你"]
    for signal in blocked_signals:
        if signal in msg:
            return "blocked"
    return "running"

def truncate(text, max_len):
    """Truncate text to max_len, adding ... if needed."""
    if len(text) <= max_len:
        return text
    return text[:max_len - 3] + "..."

def summarize_with_gemini(message, project_name):
    """Use Gemini to distill Claude's raw output into a clean summary."""
    if not API_KEY:
        return None

    # Truncate message to avoid huge API calls
    msg = message[:3000] if len(message) > 3000 else message

    prompt = (
        "你係 Mission Control 嘅摘要引擎。你嘅工作係將 AI coding agent 嘅原始輸出提煉成簡潔嘅工作摘要。\n\n"
        "規則：\n"
        "- 用書面繁體中文，唔好用口語\n"
        "- task: 一句話講而家做緊咩（最多20字），例如「實現全局快捷鍵切換面板」\n"
        "- summary: 2-3句講做咗咩、進度到邊（最多100字）\n"
        "- nextAction: 下一步要做咩（最多50字）\n"
        "- status: running(進行中) / blocked(等待用戶決定) / done(已完成)\n"
        "- 唔好重複原文，要提煉重點\n"
        "- 唔好提及檔案名，講功能\n\n"
        f"Project: {project_name}\n"
        f"AI Agent 原始輸出：\n{msg}\n\n"
        "用 JSON 回覆，不要加 markdown code block。\n"
        '格式：{"status":"...","task":"...","summary":"...","nextAction":"..."}\n'
    )
    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": 300}
    }).encode()
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={API_KEY}"

    try:
        resp = urlopen(Request(url, data=body, headers={"Content-Type": "application/json"}), timeout=8)
        data = json.loads(resp.read())
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        text = re.sub(r"```json?\s*", "", text)
        text = re.sub(r"```", "", text)
        return json.loads(text.strip())
    except:
        return None

def main():
    # Read hook input from stdin
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return
        hook_input = json.loads(raw)
    except (json.JSONDecodeError, IOError):
        return

    message = hook_input.get("last_assistant_message", "")
    cwd = hook_input.get("cwd", "")
    session_id = hook_input.get("session_id", "")

    if not message or not cwd:
        return

    project_name = get_project_name(cwd)
    agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Try Gemini summarization first, fall back to naive extraction
    result = summarize_with_gemini(message, project_name)
    if result:
        status = result.get("status", "running")
        task = truncate(result.get("task", "Working..."), 60)
        summary = truncate(result.get("summary", ""), 300)
        next_action = truncate(result.get("nextAction", ""), 200)
    else:
        status = guess_status(message)
        lines = [l.strip() for l in message.split("\n") if l.strip() and len(l.strip()) > 5]
        task = truncate(lines[0], 60) if lines else "Working..."
        summary = truncate(" ".join(lines[:3]), 300) if lines else ""
        next_action = truncate(lines[-1], 200) if lines else ""

    # Load existing agents
    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                agents = json.load(f)
        except (json.JSONDecodeError, IOError):
            agents = []

    # Update or add this agent
    found = False
    for i, a in enumerate(agents):
        if a["id"] == agent_id:
            tmux_s, tmux_w, tmux_p = detect_tmux()
            agents[i].update({
                "name": project_name,
                "status": status,
                "task": task,
                "summary": summary,
                "nextAction": next_action,
                "updatedAt": now,
                "tmuxSession": tmux_s,
                "tmuxWindow": tmux_w,
                "tmuxPane": tmux_p,
            })
            found = True
            break

    tmux_session, tmux_window, tmux_pane = detect_tmux()

    if not found:
        agents.append({
            "id": agent_id,
            "name": project_name,
            "status": status,
            "task": task,
            "summary": summary,
            "terminalLines": [],
            "nextAction": next_action,
            "updatedAt": now,
            "worktree": cwd,
            "tmuxSession": tmux_session,
            "tmuxWindow": tmux_window,
            "tmuxPane": tmux_pane,
        })

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()
