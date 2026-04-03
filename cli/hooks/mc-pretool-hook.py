#!/usr/bin/env python3
"""Claude Code PreToolUse hook — sends question to MissionControl Ask tab.

Sends the tool approval question with real options via socket.
Blocks until user responds in MissionControl UI.
"""

import json, os, sys, hashlib, subprocess, uuid, shutil

BRIDGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mc-bridge.py")

def get_tmux_info():
    """Return (session, window, pane) if running inside tmux, else (None, None, None)."""
    if not os.environ.get("TMUX"):
        return None, None, None
    tmux = shutil.which("tmux") or "/opt/homebrew/bin/tmux"
    try:
        result = subprocess.run(
            [tmux, "display-message", "-p", "#{session_name}:#{window_index}.#{pane_index}"],
            capture_output=True, text=True, timeout=5
        )
        parts = result.stdout.strip().replace(":", " ").replace(".", " ").split()
        if len(parts) == 3:
            return parts[0], int(parts[1]), int(parts[2])
    except Exception:
        pass
    return None, None, None

def main():
    try:
        raw = sys.stdin.read()
        if not raw.strip(): return
        hook_input = json.loads(raw)
    except (json.JSONDecodeError, IOError): return

    cwd = hook_input.get("cwd", "")
    if not cwd: return

    tool_name = hook_input.get("tool_name", "Unknown")
    tool_input = hook_input.get("tool_input", {})

    # Build a readable description
    desc = tool_name
    if isinstance(tool_input, dict):
        if "command" in tool_input:
            desc = f"{tool_name}: {str(tool_input['command'])[:100]}"
        elif "file_path" in tool_input:
            desc = f"{tool_name}: {tool_input['file_path']}"

    agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]
    request_id = f"req_{uuid.uuid4().hex[:12]}"

    # Claude Code permission options
    # sendKey must match what Claude Code's terminal prompt accepts
    options = json.dumps([
        {"id": "1", "label": "Yes", "sendKey": "y"},
        {"id": "2", "label": "Yes, don't ask again", "sendKey": "!"},
        {"id": "3", "label": "No", "sendKey": "n"},
    ])

    cmd = [
        sys.executable, BRIDGE, "question",
        "--agent-id", agent_id,
        "--request-id", request_id,
        "--question", f"Do you want to proceed?\n{desc}",
        "--options", options,
    ]

    session, window, pane = get_tmux_info()
    if session is not None:
        cmd += ["--tmux-session", session, "--tmux-window", str(window), "--tmux-pane", str(pane)]

    try:
        result = subprocess.run(cmd, timeout=30, capture_output=True, text=True)
        if result.stdout.strip():
            print(result.stdout.strip())
    except subprocess.TimeoutExpired:
        pass  # Auto-approve on timeout

if __name__ == "__main__":
    main()
