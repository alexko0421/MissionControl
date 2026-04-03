#!/usr/bin/env python3
"""mc-bridge — Socket client bridge for MissionControl."""

import json
import os
import socket
import sys
import argparse
import select

SOCKET_PATH = os.path.expanduser("~/.mission-control/mc.sock")
STATUS_DIR = os.path.expanduser("~/.mission-control")
STATUS_FILE = os.path.join(STATUS_DIR, "status.json")
TIMEOUT = 10


def send_and_receive(message, wait_for_response=False):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(SOCKET_PATH)
        sock.sendall((json.dumps(message) + "\n").encode())

        if not wait_for_response:
            sock.close()
            return None

        sock.setblocking(False)
        ready, _, _ = select.select([sock], [], [], TIMEOUT)
        if not ready:
            sock.close()
            return {"decision": "approve"}

        data = b""
        while True:
            ready, _, _ = select.select([sock], [], [], 1)
            if not ready:
                break
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
            if b"\n" in data:
                break

        sock.close()
        if data:
            line = data.split(b"\n")[0]
            return json.loads(line)
        return {"decision": "approve"}

    except (ConnectionRefusedError, FileNotFoundError, OSError):
        return None


def fallback_status_update(message):
    os.makedirs(STATUS_DIR, exist_ok=True)
    agents = []
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                agents = json.load(f)
        except (json.JSONDecodeError, IOError):
            agents = []

    agent_id = message.get("agent_id", "")
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    found = False
    for i, a in enumerate(agents):
        if a["id"] == agent_id:
            if message.get("status"): agents[i]["status"] = message["status"]
            if message.get("name"): agents[i]["name"] = message["name"]
            if message.get("task"): agents[i]["task"] = message["task"]
            if message.get("summary"): agents[i]["summary"] = message["summary"]
            if message.get("next_action"): agents[i]["nextAction"] = message["next_action"]
            agents[i]["updatedAt"] = now
            found = True
            break

    if not found:
        agents.append({
            "id": agent_id, "name": message.get("name", "Unknown"),
            "status": message.get("status", "running"),
            "task": message.get("task", "Working..."), "summary": message.get("summary", ""),
            "terminalLines": [], "nextAction": message.get("next_action", ""),
            "updatedAt": now, "worktree": message.get("worktree", ""),
            "app": message.get("app", "Terminal"),
        })

    with open(STATUS_FILE, "w") as f:
        json.dump(agents, f, ensure_ascii=False, indent=2)


def cmd_status(args):
    message = {"type": "status_update", "agent_id": args.agent_id, "status": args.status}
    for attr, key in [("name","name"),("task","task"),("summary","summary"),
                       ("next_action","next_action"),("worktree","worktree"),
                       ("app","app"),("agent_type","agent_type")]:
        val = getattr(args, attr, None)
        if val: message[key] = val
    if args.tmux_session: message["tmux_session"] = args.tmux_session
    if args.tmux_window is not None: message["tmux_window"] = args.tmux_window
    if args.tmux_pane is not None: message["tmux_pane"] = args.tmux_pane

    result = send_and_receive(message, wait_for_response=False)
    if result is None and not os.path.exists(SOCKET_PATH):
        fallback_status_update(message)


def cmd_permission(args):
    tool_input = {}
    if args.tool_input:
        try: tool_input = json.loads(args.tool_input)
        except json.JSONDecodeError: tool_input = {"command": args.tool_input}

    message = {
        "type": "permission_request", "agent_id": args.agent_id,
        "request_id": args.request_id, "tool": args.tool, "tool_input": tool_input,
    }
    result = send_and_receive(message, wait_for_response=True)
    if result is None: result = {"decision": "approve"}
    if result.get("decision") == "approve":
        print(json.dumps({"approve": True}))
    else:
        print(json.dumps({"decision": "block", "reason": "User denied in MissionControl"}))


def cmd_plan(args):
    message = {
        "type": "plan_review", "agent_id": args.agent_id,
        "request_id": args.request_id, "markdown": args.markdown,
    }
    result = send_and_receive(message, wait_for_response=True)
    if result is None: result = {"decision": "approve"}
    if result.get("decision") == "deny":
        print(json.dumps({"decision": "block", "reason": "User rejected plan in MissionControl"}))


def cmd_question(args):
    options = []
    if args.options:
        try: options = json.loads(args.options)
        except json.JSONDecodeError: pass

    message = {
        "type": "question", "agent_id": args.agent_id,
        "request_id": args.request_id, "question": args.question,
        "options": options,
    }
    # Include tmux info if available
    if getattr(args, "tmux_session", None):
        message["tmux_session"] = args.tmux_session
    if getattr(args, "tmux_window", None) is not None:
        message["tmux_window"] = args.tmux_window
    if getattr(args, "tmux_pane", None) is not None:
        message["tmux_pane"] = args.tmux_pane

    # Fire-and-forget: send question to MissionControl, don't wait
    # Claude Code shows its own prompt immediately
    send_and_receive(message, wait_for_response=False)


def main():
    parser = argparse.ArgumentParser(description="MissionControl bridge")
    subparsers = parser.add_subparsers(dest="command")

    sp = subparsers.add_parser("status")
    sp.add_argument("--agent-id", required=True)
    sp.add_argument("--status", required=True)
    sp.add_argument("--name"); sp.add_argument("--task"); sp.add_argument("--summary")
    sp.add_argument("--next-action"); sp.add_argument("--worktree"); sp.add_argument("--app")
    sp.add_argument("--agent-type"); sp.add_argument("--tmux-session")
    sp.add_argument("--tmux-window", type=int); sp.add_argument("--tmux-pane", type=int)

    sp = subparsers.add_parser("permission")
    sp.add_argument("--agent-id", required=True); sp.add_argument("--request-id", required=True)
    sp.add_argument("--tool", required=True); sp.add_argument("--tool-input", default="{}")

    sp = subparsers.add_parser("plan")
    sp.add_argument("--agent-id", required=True); sp.add_argument("--request-id", required=True)
    sp.add_argument("--markdown", required=True)

    sp = subparsers.add_parser("question")
    sp.add_argument("--agent-id", required=True); sp.add_argument("--request-id", required=True)
    sp.add_argument("--question", required=True); sp.add_argument("--options", default="[]")
    sp.add_argument("--tmux-session"); sp.add_argument("--tmux-window", type=int); sp.add_argument("--tmux-pane", type=int)

    args = parser.parse_args()
    if args.command == "status": cmd_status(args)
    elif args.command == "permission": cmd_permission(args)
    elif args.command == "plan": cmd_plan(args)
    elif args.command == "question": cmd_question(args)
    else: parser.print_help()


if __name__ == "__main__":
    main()
