#!/usr/bin/env python3
"""Claude Code hook — runs after each Claude response to update Mission Control.
Detects git repos being worked on, summarizes with Gemini, writes to status.json.

Usage:
  python3 mc-hook.py            # Single run (called by Claude Code hook)
  python3 mc-hook.py --daemon    # Continuous monitoring (every 30s, smart throttling)
  python3 mc-hook.py --daemon 15 # Custom interval in seconds
"""

import json
import os
import re
import sys
import subprocess
import hashlib
import time
import signal
from datetime import datetime, timezone
from urllib.request import Request, urlopen

STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
HASH_FILE = os.path.join(STATUS_DIR, ".last-hashes.json")
os.makedirs(STATUS_DIR, exist_ok=True)

# Read API key
API_KEY = os.environ.get("GEMINI_API_KEY", "")
if not API_KEY:
    key_file = os.path.join(STATUS_DIR, "gemini-key.txt")
    if os.path.exists(key_file):
        API_KEY = open(key_file).read().strip()

# Track last known hashes to avoid redundant API calls
_last_hashes = {}
if os.path.exists(HASH_FILE):
    try:
        _last_hashes = json.loads(open(HASH_FILE).read())
    except:
        _last_hashes = {}

def save_hashes():
    with open(HASH_FILE, "w") as f:
        json.dump(_last_hashes, f)

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, timeout=5).decode().strip()
    except:
        return ""

def find_git_root(path):
    """Find the git root of a path, or None."""
    root = run(f"git -C '{path}' rev-parse --show-toplevel")
    return root if root else None

def find_active_projects():
    """Find git projects being actively worked on by Claude processes."""
    projects = set()

    # 1. Check current working directory
    cwd = os.getcwd()
    root = find_git_root(cwd)
    if root:
        projects.add(root)

    # 2. Auto-detect all running dev tools and find their working directories
    #    Any process with these names → check its CWD for a git repo
    home = os.path.expanduser("~")
    all_pids = run("ps -eo pid,comm | grep -iE 'claude|codex|cursor|windsurf|aider|copilot|conductor' | awk '{print $1}'").split("\n")
    for pid in all_pids:
        pid = pid.strip()
        if not pid:
            continue
        cwd_line = run(f"lsof -p {pid} 2>/dev/null | grep cwd | head -1")
        if not cwd_line:
            continue
        idx = cwd_line.find("/")
        if idx < 0:
            continue
        tool_cwd = cwd_line[idx:].strip()
        if tool_cwd and os.path.isdir(tool_cwd):
            root = find_git_root(tool_cwd)
            if root and root != home:
                projects.add(root)

    # 3. Find git repos with recent commits (fallback)
    home = os.path.expanduser("~")
    for check_dir in ["/private/tmp", "/tmp", os.path.join(home, "Developer"), os.path.join(home, "Projects"), os.path.join(home, "Downloads")]:
        real_dir = os.path.realpath(check_dir)
        if not os.path.isdir(real_dir):
            continue
        git_dirs = run(f"find '{real_dir}' -name .git -type d -maxdepth 5 2>/dev/null")
        for git_dir in git_dirs.split("\n"):
            git_dir = git_dir.strip()
            if not git_dir:
                continue
            project = os.path.dirname(git_dir)
            if project == home:
                continue
            last_commit_age = run(f"git -C '{project}' log -1 --format='%cr' 2>/dev/null")
            if last_commit_age and ("second" in last_commit_age or "minute" in last_commit_age or "hour" in last_commit_age):
                projects.add(project)

    return list(projects)

def get_git_info(project_root):
    branch = run(f"git -C '{project_root}' branch --show-current") or "unknown"
    log = run(f"git -C '{project_root}' log --oneline -5") or "no commits"
    log_detail = run(f"git -C '{project_root}' log -3 --format='%h %s%n%b' 2>/dev/null | head -30") or ""
    diff_names = run(f"git -C '{project_root}' diff --name-only HEAD 2>/dev/null | head -15") or ""
    staged_names = run(f"git -C '{project_root}' diff --cached --name-only 2>/dev/null | head -10") or ""
    # Actual diff content (the real gold — shows WHAT is changing, not just file names)
    diff_content = run(f"git -C '{project_root}' diff HEAD --stat 2>/dev/null") or ""
    diff_snippet = run(f"git -C '{project_root}' diff HEAD -U2 2>/dev/null | head -80") or ""
    staged_snippet = run(f"git -C '{project_root}' diff --cached -U2 2>/dev/null | head -40") or ""
    untracked = run(f"git -C '{project_root}' ls-files --others --exclude-standard 2>/dev/null | head -5") or ""
    recent_files = run(f"find '{project_root}' -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/build/*' -type f -mmin -10 2>/dev/null | head -10") or ""
    remote = run(f"git -C '{project_root}' remote get-url origin 2>/dev/null") or ""
    last_msg = run(f"git -C '{project_root}' log -1 --format='%s' 2>/dev/null") or ""

    # When no uncommitted changes, show the last commit's diff instead
    # This is the common case after a Claude Code session commits its work
    last_commit_diff = ""
    if not diff_names.strip() and not staged_names.strip():
        last_commit_diff = run(f"git -C '{project_root}' diff HEAD~1..HEAD -U2 2>/dev/null | head -120") or ""

    return (
        f"Project folder: {os.path.basename(project_root)}\n"
        f"Git remote: {remote}\n"
        f"Branch: {branch}\n"
        f"Last commit: {last_msg}\n"
        f"Recent commits (with details):\n{log_detail}\n"
        f"Currently modified files (uncommitted):\n{diff_names}\n{staged_names}\n"
        f"Diff stats:\n{diff_content}\n"
        f"Actual code changes (diff snippet):\n{diff_snippet}\n"
        f"Staged changes:\n{staged_snippet}\n"
        f"Last commit diff (if no uncommitted changes):\n{last_commit_diff}\n"
        f"New untracked files:\n{untracked}\n"
        f"Recently active files (last 10 min):\n{recent_files}"
    )

def get_content_hash(git_info):
    """Hash git info to detect changes — skip API call if nothing changed."""
    return hashlib.md5(git_info.encode()).hexdigest()

def get_display_name(project_root):
    """Get a human-readable project name from git remote + folder."""
    folder = os.path.basename(project_root)
    remote = run(f"git -C '{project_root}' remote get-url origin 2>/dev/null")
    if remote:
        repo = remote.rstrip("/").split("/")[-1].replace(".git", "")
        if folder != repo and folder not in [".", ""]:
            return f"{repo} ({folder})"
        return repo
    return folder

def ask_gemini(git_info):
    if not API_KEY:
        return {"status": "running", "task": "開發中...", "summary": "需要設定 GEMINI_API_KEY", "nextAction": ""}

    prompt = (
        "你係一個 AI 工作記憶助手。你幫一個同時管理多個 AI coding agent 的開發者「回憶」每個 project 做緊乜。\n"
        "佢好容易忘記，因為佢同時有 5-10 個 AI session 在跑。你嘅總結要令佢一睇就記返起嚟。\n\n"
        "分析規則：\n"
        "1. 如果有 uncommitted changes 同 diff snippet → 呢個係此刻正在做嘅嘢，以此為主\n"
        "2. 如果冇 uncommitted changes 但有 last commit diff → 呢個係最近剛做完嘅嘢，總結呢個 commit 做咗乜\n"
        "3. 結合 commit history 理解整體背景\n"
        "4. 判斷狀態：running(有未提交變更或近10分鐘有活躍檔案), done(冇未提交變更且冇活躍檔案), blocked(極少用，只有明確等待人工時)\n\n"
        "寫 summary 嘅要求：\n"
        "- 用人話講，唔好重複 git output 原文\n"
        "- 講「做咗乜」而唔係「改咗邊個檔案」\n"
        "- 好例子：「加咗 agent 狀態變化時嘅聲音提醒同 pill 閃動動畫，令用戶唔使不停 check」\n"
        "- 壞例子：「正在修改 mc-update.sh 腳本，但具體修改內容未知」\n"
        "- 如果真係睇唔出具體做咗乜，講最近嘅 commit messages 講咗乜\n\n"
        "用繁體中文回覆 JSON。不要加 markdown code block。\n"
        '格式：{"status":"狀態","task":"具體任務描述，最多30字，要具體到功能名稱","summary":"詳細進度3-4句。用人話講做咗乜、點解做、而家到邊。","nextAction":"下一步要做什麼，要具體可執行"}\n\n'
        + git_info
    )
    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": 500}
    }).encode()
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={API_KEY}"

    try:
        resp = urlopen(Request(url, data=body, headers={"Content-Type": "application/json"}), timeout=10)
        data = json.loads(resp.read())
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        text = re.sub(r"```json?\s*", "", text)
        text = re.sub(r"```", "", text)
        return json.loads(text.strip())
    except:
        return {"status": "running", "task": "開發中...", "summary": "Gemini 回覆解析失敗", "nextAction": ""}

def update_status(force=False):
    """Main update logic. Returns number of API calls made."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    api_calls = 0

    projects = find_active_projects()
    if not projects:
        return 0

    # Load existing agents
    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            agents = json.loads(open(STATUS_FILE).read())
        except:
            agents = []

    changed = False
    for project_root in projects:
        session_name = get_display_name(project_root)
        agent_id = hashlib.md5(project_root.encode()).hexdigest()[:8]
        git_info = get_git_info(project_root)
        content_hash = get_content_hash(git_info)

        # Smart throttling: skip API call if git state hasn't changed
        if not force and _last_hashes.get(agent_id) == content_hash:
            continue

        result = ask_gemini(git_info)
        api_calls += 1
        _last_hashes[agent_id] = content_hash

        # Update or add this agent
        found = False
        for i, a in enumerate(agents):
            if a["id"] == agent_id:
                agents[i].update({
                    "name": session_name,
                    "status": result.get("status", "running"),
                    "task": result.get("task", "開發中..."),
                    "summary": result.get("summary", ""),
                    "nextAction": result.get("nextAction", ""),
                    "updatedAt": now,
                })
                found = True
                changed = True
                break

        if not found:
            agents.append({
                "id": agent_id,
                "name": session_name,
                "status": result.get("status", "running"),
                "task": result.get("task", "開發中..."),
                "summary": result.get("summary", ""),
                "terminalLines": [],
                "nextAction": result.get("nextAction", ""),
                "updatedAt": now,
                "worktree": project_root,
                "tmuxSession": None,
                "tmuxWindow": 0,
                "tmuxPane": 0,
            })
            changed = True

    # Remove agents with no git (stale entries)
    agents = [a for a in agents if a.get("task") != "無 Git 倉儲"]

    if changed or force:
        with open(STATUS_FILE, "w") as f:
            json.dump(agents, f, ensure_ascii=False, indent=2)
        save_hashes()

    return api_calls

def daemon_mode(interval=30):
    """Run continuously, polling every `interval` seconds with smart throttling."""
    print(f"🛰  MissionControl daemon started (polling every {interval}s)")
    print(f"   Status file: {STATUS_FILE}")
    print(f"   API: Gemini 2.0 Flash (smart throttled)")
    print(f"   Press Ctrl+C to stop\n")

    def handle_sigint(sig, frame):
        print("\n🛑 Daemon stopped.")
        sys.exit(0)
    signal.signal(signal.SIGINT, handle_sigint)

    cycle = 0
    total_api_calls = 0
    while True:
        cycle += 1
        try:
            ts = datetime.now().strftime("%H:%M:%S")
            calls = update_status(force=(cycle == 1))  # Force first run
            total_api_calls += calls
            if calls > 0:
                print(f"[{ts}] ✓ Updated {calls} agent(s) — total API calls: {total_api_calls}")
            else:
                # Print a dot every 5th cycle to show we're alive
                if cycle % 5 == 0:
                    print(f"[{ts}] · No changes detected (saved {total_api_calls} total API calls)")
        except Exception as e:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] ✗ Error: {e}")
        time.sleep(interval)

def main():
    # Check for daemon mode
    if len(sys.argv) > 1 and sys.argv[1] == "--daemon":
        interval = int(sys.argv[2]) if len(sys.argv) > 2 else 30
        daemon_mode(interval)
    else:
        # Single run (original hook behavior)
        update_status(force=True)

if __name__ == "__main__":
    main()
