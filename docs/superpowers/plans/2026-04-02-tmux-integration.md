# Tmux Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MissionControl and terminal both show approval prompts, with MissionControl able to answer via tmux send-keys — no AppleScript needed.

**Architecture:** Hook detects tmux environment and sends session/window/pane info with the question. MissionControl stores this and uses `tmux send-keys` to respond. Polling-based prompt detection is disabled to eliminate false positives.

**Tech Stack:** Python (hooks), Swift/SwiftUI (MissionControl), tmux

---

### Task 1: Add tmux detection to mc-pretool-hook.py

**Files:**
- Modify: `cli/hooks/mc-pretool-hook.py`
- Modify: `~/.mission-control/hooks/mc-pretool-hook.py` (deployed copy)

- [ ] **Step 1: Add tmux detection function to cli/hooks/mc-pretool-hook.py**

Add `import shutil` to the imports on line 8, then add the `get_tmux_info()` function after the `BRIDGE` constant (line 10):

```python
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
```

- [ ] **Step 2: Add tmux args to bridge call**

In the `main()` function, after the `cmd` list is built (after line 50), add tmux args:

```python
    session, window, pane = get_tmux_info()
    if session is not None:
        cmd += ["--tmux-session", session, "--tmux-window", str(window), "--tmux-pane", str(pane)]
```

- [ ] **Step 3: Copy to deployed location**

```bash
cp cli/hooks/mc-pretool-hook.py ~/.mission-control/hooks/mc-pretool-hook.py
```

- [ ] **Step 4: Commit**

```bash
git add cli/hooks/mc-pretool-hook.py
git commit -m "feat: detect tmux env and send session info in pretool hook"
```

---

### Task 2: Add tmux args to mc-bridge.py question command

**Files:**
- Modify: `cli/hooks/mc-bridge.py`
- Modify: `~/.mission-control/hooks/mc-bridge.py` (deployed copy)

- [ ] **Step 1: Add tmux args to question subparser**

In `main()`, find the question subparser (currently at line 177-179). Add three optional args:

```python
    sp = subparsers.add_parser("question")
    sp.add_argument("--agent-id", required=True); sp.add_argument("--request-id", required=True)
    sp.add_argument("--question", required=True); sp.add_argument("--options", default="[]")
    sp.add_argument("--tmux-session"); sp.add_argument("--tmux-window", type=int); sp.add_argument("--tmux-pane", type=int)
```

- [ ] **Step 2: Include tmux fields in cmd_question message**

Replace the `cmd_question` function (line 140-155) with:

```python
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
```

- [ ] **Step 3: Copy to deployed location**

```bash
cp cli/hooks/mc-bridge.py ~/.mission-control/hooks/mc-bridge.py
```

- [ ] **Step 4: Commit**

```bash
git add cli/hooks/mc-bridge.py
git commit -m "feat: pass tmux session info through bridge question command"
```

---

### Task 3: Store tmux info from question messages in AgentStore

**Files:**
- Modify: `MissionControl/AgentStore.swift:345-382`

- [ ] **Step 1: Update handleQuestion to store tmux fields**

In `handleQuestion` (line 345), after finding/creating the agent and before setting `pendingQuestion`, store tmux info from the message. Replace lines 375-382:

```swift
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            // Store tmux info from question message if available
            if let session = msg.tmuxSession {
                agents[idx].tmuxSession = session
                agents[idx].tmuxWindow = msg.tmuxWindow
                agents[idx].tmuxPane = msg.tmuxPane
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingQuestion = agentQuestion
                agents[idx].status = .blocked
                agents[idx].updatedAt = Date()
            }
            triggerAlert(for: agents[idx])
            autoSwitchTab()
        }
```

- [ ] **Step 2: Verify tmuxTarget computed property exists on Agent model**

Check `Models.swift` to confirm `Agent` has a `tmuxTarget` computed property that builds `"session:window.pane"` from `tmuxSession`, `tmuxWindow`, `tmuxPane`. This should already exist — verify it.

- [ ] **Step 3: Build and verify no compile errors**

```bash
xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add MissionControl/AgentStore.swift
git commit -m "feat: store tmux info from question messages for send-keys response"
```

---

### Task 4: Disable prompt detection in polling

**Files:**
- Modify: `MissionControl/AgentStore.swift:135-170`

- [ ] **Step 1: Remove detectPrompt call from pollTerminals**

In `pollTerminals()` (starting at line 143), change the Task.detached block to only capture terminal lines, not detect prompts. Replace the full `pollTerminals` method:

```swift
    private func pollTerminals() {
        for i in agents.indices {
            guard let target = agents[i].tmuxTarget else { continue }

            Task.detached {
                let lines = TMuxBridge.capturePane(target: target)

                await MainActor.run { [weak self, lines] in
                    guard let self = self,
                          let idx = self.agents.firstIndex(where: { $0.tmuxTarget == target }) else { return }
                    if !lines.isEmpty {
                        self.agents[idx].terminalLines = lines
                    }
                    // Clear question if agent is no longer blocked
                    if self.agents[idx].status != .blocked && self.agents[idx].pendingQuestion != nil {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.agents[idx].pendingQuestion = nil
                        }
                    }
                }
            }
        }
    }
```

Key changes:
- Removed `let status = agents[i].status` — no longer needed
- Removed `TMuxBridge.detectPrompt(target:)` call
- Removed the `if let prompt = prompt` block that created fake questions
- Kept terminal line updates and stale question cleanup

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add MissionControl/AgentStore.swift
git commit -m "fix: disable polling-based prompt detection, hook is single source of truth"
```

---

### Task 5: Add question_resolved handling to clear stale questions

**Files:**
- Modify: `cli/hooks/mc-posttool-hook.py`
- Modify: `cli/hooks/mc-bridge.py`
- Modify: `MissionControl/SocketMessage.swift`
- Modify: `MissionControl/AgentStore.swift`
- Modify: `~/.mission-control/hooks/mc-posttool-hook.py` (deployed copy)
- Modify: `~/.mission-control/hooks/mc-bridge.py` (deployed copy)

- [ ] **Step 1: Add question_resolved message type to SocketMessage.swift**

Add `questionResolved` to the `IncomingMessageType` enum (line 5-10):

```swift
enum IncomingMessageType: String, Codable {
    case statusUpdate = "status_update"
    case permissionRequest = "permission_request"
    case planReview = "plan_review"
    case question = "question"
    case questionResolved = "question_resolved"
}
```

- [ ] **Step 2: Add question_resolved handler in MCSocketServer routing**

In `AgentStore.swift`, in `setupSocketServer()` where callbacks are registered, add a handler for the new message type. Find the existing `onQuestion` handler setup and add after it:

```swift
        socketServer.onQuestionResolved = { [weak self] msg in
            guard let self = self, let agentId = msg.agentId else { return }
            if let idx = self.agents.firstIndex(where: { $0.id == agentId }) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.agents[idx].pendingQuestion = nil
                    if self.agents[idx].status == .blocked {
                        self.agents[idx].status = .running
                    }
                    self.agents[idx].updatedAt = Date()
                }
                self.collapseIfNoPending()
            }
        }
```

- [ ] **Step 3: Add onQuestionResolved callback to MCSocketServer.swift**

In `MCSocketServer.swift`, add the callback property alongside the existing ones:

```swift
    var onQuestionResolved: ((IncomingMessage) -> Void)?
```

And in `handleMessage(_:from:)`, add the routing case:

```swift
        case .questionResolved:
            onQuestionResolved?(message)
```

- [ ] **Step 4: Add question_resolved command to mc-bridge.py**

Add a new command function after `cmd_question`:

```python
def cmd_question_resolved(args):
    message = {
        "type": "question_resolved",
        "agent_id": args.agent_id,
    }
    send_and_receive(message, wait_for_response=False)
```

Add subparser in `main()`:

```python
    sp = subparsers.add_parser("question-resolved")
    sp.add_argument("--agent-id", required=True)
```

Add dispatch in the `if/elif` chain:

```python
    elif args.command == "question-resolved": cmd_question_resolved(args)
```

- [ ] **Step 5: Update mc-posttool-hook.py to send question_resolved**

Replace the current content of `mc-posttool-hook.py`:

```python
#!/usr/bin/env python3
"""Claude Code PostToolUse hook — clears pending question and marks agent running."""

import json, os, sys, hashlib, subprocess

BRIDGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mc-bridge.py")

def main():
    try:
        raw = sys.stdin.read()
        if not raw.strip(): return
        hook_input = json.loads(raw)
    except (json.JSONDecodeError, IOError): return

    cwd = hook_input.get("cwd", "")
    if not cwd: return

    agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]

    # Clear pending question
    subprocess.run([sys.executable, BRIDGE, "question-resolved",
        "--agent-id", agent_id], timeout=5, capture_output=True)

    # Update status to running
    subprocess.run([sys.executable, BRIDGE, "status",
        "--agent-id", agent_id, "--status", "running"], timeout=5, capture_output=True)

if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Copy hooks to deployed location**

```bash
cp cli/hooks/mc-bridge.py ~/.mission-control/hooks/mc-bridge.py
cp cli/hooks/mc-posttool-hook.py ~/.mission-control/hooks/mc-posttool-hook.py
```

- [ ] **Step 7: Build and verify**

```bash
xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5
```

- [ ] **Step 8: Commit**

```bash
git add cli/hooks/mc-bridge.py cli/hooks/mc-posttool-hook.py MissionControl/AgentStore.swift MissionControl/MCSocketServer.swift MissionControl/SocketMessage.swift
git commit -m "feat: add question_resolved flow to clear stale questions after tool completes"
```

---

### Task 6: End-to-end test in tmux

- [ ] **Step 1: Start tmux session**

```bash
tmux new-session -s test
```

- [ ] **Step 2: Launch Claude Code inside tmux**

```bash
claude
```

- [ ] **Step 3: Build and run MissionControl from Xcode**

Rebuild in Xcode with the new changes.

- [ ] **Step 4: Trigger a tool call in Claude Code**

Ask Claude to read a file or run a command that requires approval.

- [ ] **Step 5: Verify both prompts appear**

- Terminal shows Claude Code's permission prompt
- MissionControl shows the same question in Ask tab

- [ ] **Step 6: Click Yes in MissionControl**

Verify:
- Terminal receives the keystroke via tmux send-keys
- Claude Code proceeds with the tool
- MissionControl clears the question card (via PostToolUse hook)

- [ ] **Step 7: Test terminal-side approval**

Trigger another tool call, this time approve in terminal directly.
Verify MissionControl clears the question card after tool completes.

- [ ] **Step 8: Verify no fake options**

Use Claude Code for several tool calls. Confirm MissionControl only shows questions from the hook — no phantom prompts from polling.

- [ ] **Step 9: Commit all final changes and push**

```bash
git add -A
git commit -m "test: verified tmux integration end-to-end"
git push
```
