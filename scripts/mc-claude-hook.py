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

def detect_app():
    """Detect which app this Claude session is running in."""
    bundle_id = os.environ.get("__CFBundleIdentifier", "")
    mapping = {
        "com.apple.Terminal": "Terminal",
        "com.google.antigravity": "Antigravity",
    }
    if bundle_id in mapping:
        return mapping[bundle_id]
    # Check parent process for conductor/codex
    try:
        ppid = os.getppid()
        while ppid > 1:
            cmd = subprocess.check_output(
                ["ps", "-p", str(ppid), "-o", "comm="],
                stderr=subprocess.DEVNULL, timeout=3
            ).decode().strip()
            cmd_lower = cmd.lower()
            if "conductor" in cmd_lower:
                return "Conductor"
            if "codex" in cmd_lower:
                return "Codex"
            if "antigravity" in cmd_lower:
                return "Antigravity"
            # Get parent of parent
            ppid_str = subprocess.check_output(
                ["ps", "-p", str(ppid), "-o", "ppid="],
                stderr=subprocess.DEVNULL, timeout=3
            ).decode().strip()
            ppid = int(ppid_str)
    except:
        pass
    if bundle_id:
        # Return bundle name as fallback
        parts = bundle_id.split(".")
        return parts[-1].capitalize() if parts else "Terminal"
    return "Terminal"

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
        "option a", "option b", "option 1", "option 2",
        "approach a", "approach b", "approach 1", "approach 2",
        "which do you", "which would you", "what would you",
        "your decision", "your input", "your feedback",
        "select one", "pick between", "decide between",
        # Simplified Chinese
        "你想", "你觉得", "要你决定", "需要你", "你的意见", "请选择",
        "你选", "你希望", "你认为", "请确认", "你来决定", "你决定",
        "方案a", "方案b", "方案1", "方案2", "选项a", "选项b",
        "哪个", "哪种", "要哪", "选哪", "你要",
        # Traditional Chinese
        "你覺得", "你選", "你希望", "你認為", "請確認", "請選擇",
        "你來決定", "邊個", "邊種",
    ]
    # Question mark at end of last few lines is a strong signal
    lines = [l.strip() for l in message.strip().split("\n") if l.strip()]
    for line in lines[-3:]:  # check last 3 lines
        if line.endswith("?") or line.endswith("？") or line.endswith("吗") or line.endswith("嗎") or line.endswith("呢"):
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

def get_app_language():
    """Read app language setting from UserDefaults."""
    try:
        result = subprocess.check_output(
            ["defaults", "read", "com.yourcompany.MissionControl", "appLanguage"],
            stderr=subprocess.DEVNULL, timeout=3
        ).decode().strip()
        return result if result in ("En", "Zh") else "Zh"
    except:
        return "Zh"

def summarize_with_gemini(message, project_name):
    """Use Gemini to distill Claude's raw output into a clean summary."""
    if not API_KEY:
        return None

    lang = get_app_language()

    # Truncate message to avoid huge API calls
    msg = message[:3000] if len(message) > 3000 else message

    if lang == "En":
        prompt = (
            "You are Mission Control's summary engine. Distill AI coding agent output into a clean summary.\n\n"
            "Rules:\n"
            "- Use concise English\n"
            "- task: one sentence about current work (max 40 chars), e.g. 'Implement global hotkey toggle'\n"
            "- summary: 2-3 sentences about what was done and progress (max 200 chars)\n"
            "- nextAction: what to do next (max 100 chars)\n"
            "- status rules (very important):\n"
            "  - blocked: message ends with question mark, or asks user to choose/decide/confirm\n"
            "  - done: explicitly says 'done'/'complete' with no follow-up questions\n"
            "  - running: all other cases\n"
            "- Do not repeat raw output, distill key points\n"
            "- Describe features, not filenames\n\n"
            f"Project: {project_name}\n"
            f"AI Agent raw output:\n{msg}\n\n"
            "Reply in JSON only, no markdown code block.\n"
            'Format: {"status":"...","task":"...","summary":"...","nextAction":"..."}\n'
        )
    else:
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
    stop_reason = hook_input.get("stop_reason", "")

    # Debug: log raw hook input to see available fields
    debug_file = os.path.join(STATUS_DIR, "hook-debug.json")
    with open(debug_file, "w") as df:
        json.dump({"keys": list(hook_input.keys()), "stop_reason": stop_reason, "raw_sample": {k: str(v)[:200] for k, v in hook_input.items()}}, df, indent=2)

    if not message or not cwd:
        return

    project_name = get_project_name(cwd)
    agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # If Claude stopped because it wants to use a tool → likely waiting for user approval
    is_tool_use_stop = (stop_reason == "tool_use")

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

    # Override: tool_use stop means Claude is waiting for approval → blocked
    if is_tool_use_stop and status != "done":
        status = "blocked"

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
    app_name = detect_app()
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
                "app": app_name,
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
            "app": app_name,
            "tmuxSession": tmux_session,
            "tmuxWindow": tmux_window,
            "tmuxPane": tmux_pane,
        })

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()
