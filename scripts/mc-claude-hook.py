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
    blocked_signals = [
        # English
        "which option", "do you want", "should i", "please choose", "waiting for",
        "need your", "what do you think", "let me know", "your choice", "pick one",
        "would you like", "want me to", "prefer", "choose between",
        # Simplified Chinese
        "你想", "你觉得", "要你决定", "需要你", "你的意见", "请选择",
        "你选", "你希望", "你认为", "请确认",
    ]
    # Question mark at end of message is a strong signal
    last_line = message.strip().split("\n")[-1].strip() if message.strip() else ""
    if last_line.endswith("?") or last_line.endswith("？"):
        return "blocked"
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
        "你是 Mission Control 的摘要引擎。你的工作是将 AI coding agent 的原始输出提炼成简洁的工作摘要。\n\n"
        "规则：\n"
        "- 用简体中文书面语\n"
        "- task: 一句话讲当前在做什么（最多20字），例如「实现全局快捷键切换面板」\n"
        "- summary: 2-3句讲做了什么、进度到哪（最多100字）\n"
        "- nextAction: 下一步要做什么（最多50字）\n"
        "- status 判断规则（非常重要）：\n"
        "  - blocked: 消息结尾有问号、或要求用户做选择/决定/确认\n"
        "  - done: 明确说「完成」「done」且没有后续问题\n"
        "  - running: 其他所有情况（正在工作、刚做完但还有下一步）\n"
        "- 不要重复原文，要提炼重点\n"
        "- 不要提及文件名，讲功能\n\n"
        f"Project: {project_name}\n"
        f"AI Agent 原始输出：\n{msg}\n\n"
        "用 JSON 回复，不要加 markdown code block。\n"
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
