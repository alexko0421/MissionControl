#!/usr/bin/env python3
"""mc-scan.py — Scan running Claude Code sessions, summarize with Gemini, update Mission Control"""

import json
import os
import re
import subprocess
import hashlib
from datetime import datetime, timezone
from urllib.request import Request, urlopen
from urllib.error import URLError

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
API_KEY = os.environ.get("GEMINI_API_KEY", "")

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, timeout=5).decode().strip()
    except:
        return ""

def get_git_info(cwd):
    if not run(f"git -C '{cwd}' rev-parse --git-dir"):
        return f"Directory: {cwd} (no git)"
    branch = run(f"git -C '{cwd}' branch --show-current") or "unknown"
    log = run(f"git -C '{cwd}' log --oneline -5") or "no commits"
    status = run(f"git -C '{cwd}' status --short | head -10") or "clean"
    return f"Branch: {branch}\nRecent commits:\n{log}\nChanged files:\n{status}"

def ask_gemini(git_info):
    if not API_KEY:
        return {"task": "開發中...", "summary": "GEMINI_API_KEY 未設定", "nextAction": "設定 API key"}

    prompt = (
        "根據以下 git 資訊，用繁體中文回覆 JSON。不要加 markdown code block。"
        '格式：{"task": "一句話描述（最多20字）", "summary": "2-3句摘要", "nextAction": "下一步建議"}\n\n'
        + git_info
    )

    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": 300}
    }).encode()

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={API_KEY}"
    req = Request(url, data=body, headers={"Content-Type": "application/json"})

    try:
        resp = urlopen(req, timeout=10)
        data = json.loads(resp.read())
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        text = re.sub(r"```json?\s*", "", text)
        text = re.sub(r"```", "", text)
        return json.loads(text.strip())
    except Exception as e:
        return {"task": "開發中...", "summary": f"Gemini 回覆解析失敗", "nextAction": "稍後重試"}

def find_claude_sessions():
    """Find working directories of running Claude Code CLI processes."""
    # Find PIDs of Claude Code CLI (not the desktop app)
    pids_raw = run("ps aux | grep -E '[c]laude$' | awk '{print $2}'")
    if not pids_raw:
        # Also try matching the CLI binary
        pids_raw = run("pgrep -f 'claude' | head -5")
    if not pids_raw:
        return []

    cwds = set()
    for pid in pids_raw.split("\n"):
        pid = pid.strip()
        if not pid:
            continue
        # Get working directory via lsof
        cwd = run(f"lsof -p {pid} 2>/dev/null | grep cwd | awk '{{print $NF}}'")
        if cwd and os.path.isdir(cwd) and cwd != "/":
            cwds.add(cwd)
    return list(cwds)

def main():
    os.makedirs(STATUS_DIR, exist_ok=True)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    cwds = find_claude_sessions()
    if not cwds:
        print("✓ No Claude sessions found")
        return

    agents = []
    for cwd in cwds:
        name = os.path.basename(cwd)
        git_info = get_git_info(cwd)
        result = ask_gemini(git_info)
        agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]

        agents.append({
            "id": agent_id,
            "name": name,
            "status": "running",
            "task": result.get("task", "開發中..."),
            "summary": result.get("summary", ""),
            "terminalLines": [],
            "nextAction": result.get("nextAction", ""),
            "updatedAt": now,
            "worktree": cwd,
            "tmuxSession": None,
            "tmuxWindow": 0,
            "tmuxPane": 0,
        })
        print(f"  ✓ {name}: {result.get('task', '?')}")

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)
    print(f"✓ Mission Control updated with {len(agents)} agent(s)")

if __name__ == "__main__":
    main()
