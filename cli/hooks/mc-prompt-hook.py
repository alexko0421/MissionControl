#!/usr/bin/env python3
"""Claude Code UserPromptSubmit hook — marks agent as 'running' via mc-bridge."""

import json, os, sys, hashlib, subprocess

BRIDGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mc-bridge.py")

def _get_name(cwd):
    try:
        branch = subprocess.check_output(
            ["git", "-C", cwd, "branch", "--show-current"],
            stderr=subprocess.DEVNULL, timeout=3).decode().strip()
        if branch:
            if "/" in branch: branch = branch.split("/", 1)[1]
            return branch.replace("-", " ").replace("_", " ")
    except Exception: pass
    return os.path.basename(cwd)

def _detect_app():
    bundle_id = os.environ.get("__CFBundleIdentifier", "")
    mapping = {"com.apple.Terminal": "Terminal", "com.google.antigravity": "Antigravity"}
    if bundle_id in mapping: return mapping[bundle_id]
    try:
        ppid = os.getppid()
        while ppid > 1:
            cmd = subprocess.check_output(["ps", "-p", str(ppid), "-o", "comm="],
                stderr=subprocess.DEVNULL, timeout=3).decode().strip().lower()
            if "conductor" in cmd: return "Conductor"
            if "codex" in cmd: return "Codex"
            ppid_str = subprocess.check_output(["ps", "-p", str(ppid), "-o", "ppid="],
                stderr=subprocess.DEVNULL, timeout=3).decode().strip()
            ppid = int(ppid_str)
    except Exception: pass
    return "Terminal"

def _detect_tmux():
    if not os.environ.get("TMUX"): return None, 0, 0
    try:
        s = subprocess.check_output(["tmux", "display-message", "-p", "#{session_name}"],
            stderr=subprocess.DEVNULL, timeout=3).decode().strip()
        w = subprocess.check_output(["tmux", "display-message", "-p", "#{window_index}"],
            stderr=subprocess.DEVNULL, timeout=3).decode().strip()
        p = subprocess.check_output(["tmux", "display-message", "-p", "#{pane_index}"],
            stderr=subprocess.DEVNULL, timeout=3).decode().strip()
        return s or None, int(w or 0), int(p or 0)
    except Exception: return None, 0, 0

def main():
    try:
        raw = sys.stdin.read()
        if not raw.strip(): return
        hook_input = json.loads(raw)
    except (json.JSONDecodeError, IOError): return

    cwd = hook_input.get("cwd", "")
    if not cwd: return

    agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]
    cmd = [sys.executable, BRIDGE, "status",
        "--agent-id", agent_id, "--status", "running",
        "--name", _get_name(cwd), "--task", "處理中...",
        "--worktree", cwd, "--app", _detect_app(), "--agent-type", "claude-code"]
    tmux_s, tmux_w, tmux_p = _detect_tmux()
    if tmux_s: cmd += ["--tmux-session", tmux_s, "--tmux-window", str(tmux_w), "--tmux-pane", str(tmux_p)]
    subprocess.run(cmd, timeout=5, capture_output=True)

if __name__ == "__main__":
    main()
