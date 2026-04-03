# Inline Permission Approval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a permission card in MissionControl's floating window when Claude Code needs tool approval; user can click Allow/Deny to respond via tmux, or respond in terminal as usual.

**Architecture:** PreToolUse hook (fire-and-forget) sends permission info via socket → MC shows card → user clicks → tmux send-keys responds. PostToolUse hook auto-dismisses card regardless of how the user responded.

**Tech Stack:** Python (hooks), Swift/SwiftUI (MC app), Unix domain sockets

---

### File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `~/.mission-control/hooks/mc-pretool-hook.py` | Create | Send permission_request via socket (fire-and-forget) |
| `~/.mission-control/hooks/mc-posttool-hook.py` | Modify | Already sends question_resolved; add session_id for agent_id |
| `MissionControl/Models.swift` | Modify | Add `PermissionRequest` struct + `pendingPermission` on Agent |
| `MissionControl/AgentStore.swift` | Modify | Add `handlePermissionRequest()`, `respondPermission()`, wire up socket handler |
| `MissionControl/PermissionCardView.swift` | Create | Card UI: tool info, diff preview, Allow/Deny buttons |
| `MissionControl/ContentView.swift` | Modify | Show PermissionCardView in approve tab |
| `MissionControl/MCSocketServer.swift` | No change | Already has `onPermissionRequest` callback |

---

### Task 1: Create PreToolUse hook

**Files:**
- Create: `~/.mission-control/hooks/mc-pretool-hook.py`

- [ ] **Step 1: Write the hook**

```python
#!/usr/bin/env python3
"""PreToolUse hook — sends permission_request to MissionControl (fire-and-forget)."""

import json, os, sys, hashlib, subprocess, uuid, shutil

BRIDGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mc-bridge.py")


def get_tmux_info():
    tmux = shutil.which("tmux") or "/opt/homebrew/bin/tmux"
    try:
        result = subprocess.run(
            [tmux, "display-message", "-p", "#{session_name}:#{window_index}.#{pane_index}"],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode != 0:
            return None, None, None
        parts = result.stdout.strip().replace(":", " ").replace(".", " ").split()
        if len(parts) == 3:
            return parts[0], int(parts[1]), int(parts[2])
    except Exception:
        pass
    return None, None, None


def get_project_name(cwd):
    if not cwd:
        return "Unknown"
    try:
        branch = subprocess.check_output(
            ["git", "-C", cwd, "branch", "--show-current"],
            stderr=subprocess.DEVNULL, timeout=3
        ).decode().strip()
        if branch:
            if "/" in branch:
                branch = branch.split("/", 1)[1]
            return branch.replace("-", " ").replace("_", " ")
    except Exception:
        pass
    return os.path.basename(cwd)


def main():
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return
        hook_input = json.loads(raw)
    except (json.JSONDecodeError, IOError):
        return

    cwd = hook_input.get("cwd", "")
    session_id = hook_input.get("session_id", "")
    if not cwd:
        return

    tool_name = hook_input.get("tool_name", "Unknown")
    tool_input = hook_input.get("tool_input", {})
    if not isinstance(tool_input, dict):
        tool_input = {"command": str(tool_input)}

    agent_id = session_id[:8] if session_id else hashlib.md5(cwd.encode()).hexdigest()[:8]
    request_id = f"perm_{uuid.uuid4().hex[:12]}"
    name = get_project_name(cwd)

    session, window, pane = get_tmux_info()

    # Fire-and-forget: send permission_request to MC, don't block
    message = {
        "type": "permission_request",
        "agent_id": agent_id,
        "request_id": request_id,
        "tool": tool_name,
        "tool_input": {k: str(v) for k, v in tool_input.items()},
        "name": name,
    }
    if session is not None:
        message["tmux_session"] = session
        message["tmux_window"] = window
        message["tmux_pane"] = pane

    # Send directly via socket (faster than spawning mc-bridge.py)
    import socket as sock_mod
    socket_path = os.path.expanduser("~/.mission-control/mc.sock")
    try:
        s = sock_mod.socket(sock_mod.AF_UNIX, sock_mod.SOCK_STREAM)
        s.connect(socket_path)
        s.sendall((json.dumps(message) + "\n").encode())
        s.close()
    except (ConnectionRefusedError, FileNotFoundError, OSError):
        pass


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify hook runs**

```bash
echo '{"cwd":"/tmp","session_id":"test1234","tool_name":"Bash","tool_input":{"command":"ls"}}' | python3 ~/.mission-control/hooks/mc-pretool-hook.py
```

Expected: no output, no error (fire-and-forget).

- [ ] **Step 3: Commit**

```bash
git add -f ~/.mission-control/hooks/mc-pretool-hook.py
git commit -m "feat: add pretool hook for permission card (fire-and-forget)"
```

---

### Task 2: Fix PostToolUse hook to use session_id

**Files:**
- Modify: `~/.mission-control/hooks/mc-posttool-hook.py`

- [ ] **Step 1: Update agent_id to use session_id**

Replace the `agent_id` line:

```python
# Old:
agent_id = hashlib.md5(cwd.encode()).hexdigest()[:8]

# New:
session_id = hook_input.get("session_id", "")
agent_id = session_id[:8] if session_id else hashlib.md5(cwd.encode()).hexdigest()[:8]
```

- [ ] **Step 2: Commit**

```bash
git add -f ~/.mission-control/hooks/mc-posttool-hook.py
git commit -m "fix: use session_id for agent_id in posttool hook"
```

---

### Task 3: Add PermissionRequest model and pendingPermission to Agent

**Files:**
- Modify: `MissionControl/Models.swift`

- [ ] **Step 1: Add PermissionRequest struct**

Add after the `TerminalLine` struct (around line 68):

```swift
// MARK: - Permission Request

struct PermissionRequest: Identifiable {
    var id: String
    var tool: String
    var toolInput: [String: String]
    var receivedAt: Date
}
```

- [ ] **Step 2: Add pendingPermission to Agent**

Add to Agent struct properties, after `agentType`:

```swift
var pendingPermission: PermissionRequest? = nil
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme MissionControl -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add MissionControl/Models.swift
git commit -m "feat: add PermissionRequest model and pendingPermission on Agent"
```

---

### Task 4: Wire up handlePermissionRequest and respondPermission in AgentStore

**Files:**
- Modify: `MissionControl/AgentStore.swift`

- [ ] **Step 1: Wire up onPermissionRequest in setupSocketServer()**

Add after `socketServer.onStatusUpdate` handler:

```swift
socketServer.onPermissionRequest = { [weak self] msg, clientFD in
    self?.handlePermissionRequest(msg)
}
```

Note: we don't need `clientFD` because this is fire-and-forget (no response sent back to hook).

- [ ] **Step 2: Add handlePermissionRequest()**

Add after `handleStatusUpdate()`:

```swift
private func handlePermissionRequest(_ msg: IncomingMessage) {
    guard let agentId = msg.agentId,
          let requestId = msg.requestId,
          let tool = msg.tool else { return }

    let request = PermissionRequest(
        id: requestId,
        tool: tool,
        toolInput: msg.toolInput ?? [:],
        receivedAt: Date()
    )

    if let idx = agents.firstIndex(where: { $0.id == agentId }) {
        // Store tmux info if provided
        if let session = msg.tmuxSession {
            agents[idx].tmuxSession = session
            agents[idx].tmuxWindow = msg.tmuxWindow
            agents[idx].tmuxPane = msg.tmuxPane
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            agents[idx].pendingPermission = request
            agents[idx].status = .blocked
            agents[idx].updatedAt = Date()
        }
        triggerAlert(for: agents[idx])
        autoSwitchTab()
    } else {
        // Agent not yet registered — create it
        var agent = Agent(
            id: agentId,
            name: msg.name ?? agentId,
            status: .blocked,
            task: "\(tool) approval",
            summary: "",
            terminalLines: [],
            nextAction: "",
            updatedAt: Date(),
            tmuxSession: msg.tmuxSession,
            tmuxWindow: msg.tmuxWindow,
            tmuxPane: msg.tmuxPane
        )
        agent.pendingPermission = request
        withAnimation(.easeInOut(duration: 0.2)) {
            agents.append(agent)
        }
        triggerAlert(for: agent)
        autoSwitchTab()
    }
}
```

- [ ] **Step 3: Add respondPermission()**

Add after `handlePermissionRequest()`:

```swift
func respondPermission(agentId: String, allow: Bool) {
    guard let idx = agents.firstIndex(where: { $0.id == agentId }) else { return }
    let sendKey = allow ? "y" : "n"

    if let target = agents[idx].tmuxTarget {
        Task.detached {
            TMuxBridge.sendKeys(target: target, command: sendKey)
        }
    }

    withAnimation(.easeInOut(duration: 0.2)) {
        agents[idx].pendingPermission = nil
        agents[idx].status = allow ? .running : agents[idx].status
        agents[idx].updatedAt = Date()
    }
    collapseIfNoPending()
}
```

- [ ] **Step 4: Update approveAgents computed property**

Find the `approveAgents` computed property and add `pendingPermission`:

```swift
var approveAgents: [Agent] {
    agents.filter { $0.pendingPermission != nil || $0.pendingPlan != nil }
}
```

- [ ] **Step 5: Update collapseIfNoPending()**

Find `collapseIfNoPending()` and add `pendingPermission`:

```swift
let hasPending = agents.contains {
    $0.pendingPermission != nil || $0.pendingPlan != nil || $0.pendingQuestion != nil
}
```

- [ ] **Step 6: Update onQuestionResolved to also clear pendingPermission**

In the `onQuestionResolved` handler, add:

```swift
self.agents[idx].pendingPermission = nil
```

- [ ] **Step 7: Build and verify**

```bash
xcodebuild -scheme MissionControl -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 8: Commit**

```bash
git add MissionControl/AgentStore.swift
git commit -m "feat: add permission request handling and tmux response in AgentStore"
```

---

### Task 5: Create PermissionCardView

**Files:**
- Create: `MissionControl/PermissionCardView.swift`

- [ ] **Step 1: Write PermissionCardView**

```swift
import SwiftUI

struct PermissionCardView: View {
    let agent: Agent
    let permission: PermissionRequest
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
                Text(permission.tool)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(agent.name)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // File path
            if let filePath = permission.toolInput["file_path"], !filePath.isEmpty {
                Text(shortenPath(filePath))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Command (Bash)
            if let command = permission.toolInput["command"], !command.isEmpty {
                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(command)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Diff preview (Edit tool)
            if permission.tool.lowercased().contains("edit") {
                diffPreview
            }

            // Two buttons
            HStack(spacing: 8) {
                Button(action: { store.respondPermission(agentId: agent.id, allow: false) }) {
                    Text("Deny")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.25, green: 0.25, blue: 0.28))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: { store.respondPermission(agentId: agent.id, allow: true) }) {
                    Text("Allow")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.204, green: 0.827, blue: 0.600))
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.937, green: 0.624, blue: 0.153).opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
    }

    // MARK: - Diff Preview

    @ViewBuilder
    private var diffPreview: some View {
        let oldLines = (permission.toolInput["old_string"] ?? "").components(separatedBy: "\n")
        let newLines = (permission.toolInput["new_string"] ?? "").components(separatedBy: "\n")

        if !oldLines.isEmpty || !newLines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(oldLines.prefix(6).enumerated()), id: \.offset) { _, line in
                    diffLine(text: line, type: .deletion)
                }
                ForEach(Array(newLines.prefix(6).enumerated()), id: \.offset) { _, line in
                    diffLine(text: line, type: .addition)
                }
                if oldLines.count > 6 || newLines.count > 6 {
                    Text("  ...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func diffLine(text: String, type: DiffType) -> some View {
        HStack(spacing: 0) {
            Text(type == .addition ? "+ " : "- ")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(type == .addition
                    ? Color(red: 0.30, green: 0.85, blue: 0.50).opacity(0.7)
                    : Color(red: 0.90, green: 0.35, blue: 0.35).opacity(0.7))
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(type == .addition
                    ? Color(red: 0.30, green: 0.85, blue: 0.50)
                    : Color(red: 0.90, green: 0.35, blue: 0.35))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(type == .addition
            ? Color(red: 0.15, green: 0.35, blue: 0.20).opacity(0.5)
            : Color(red: 0.35, green: 0.15, blue: 0.15).opacity(0.5))
    }

    private enum DiffType { case addition, deletion }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

Add `PermissionCardView.swift` to `MissionControl.xcodeproj/project.pbxproj` — same pattern as other Swift files (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase).

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme MissionControl -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add MissionControl/PermissionCardView.swift MissionControl.xcodeproj/project.pbxproj
git commit -m "feat: add PermissionCardView with diff preview and Allow/Deny buttons"
```

---

### Task 6: Show PermissionCardView in ContentView approve tab

**Files:**
- Modify: `MissionControl/ContentView.swift`

- [ ] **Step 1: Add PermissionCardView to approve tab**

Find the `ForEach(pendingAgents)` block in the approve tab (around line 449) and add the permission card:

```swift
// Current:
ForEach(pendingAgents) { agent in
    if let plan = agent.pendingPlan {
        PlanReviewView(agent: agent, plan: plan)
    }
}

// New:
ForEach(pendingAgents) { agent in
    if let permission = agent.pendingPermission {
        PermissionCardView(agent: agent, permission: permission)
    }
    if let plan = agent.pendingPlan {
        PlanReviewView(agent: agent, plan: plan)
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme MissionControl -configuration Release -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add MissionControl/ContentView.swift
git commit -m "feat: show permission card in approve tab"
```

---

### Task 7: Register hooks in settings.json and test end-to-end

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: Ensure PreToolUse and PostToolUse hooks are registered**

Verify `~/.claude/settings.json` has MC hooks for PreToolUse and PostToolUse. They should already be there — just confirm the paths are correct:

```json
"PreToolUse": [
  {
    "hooks": [{"type": "command", "command": "python3 /Users/kochunlong/.mission-control/hooks/mc-pretool-hook.py"}],
    "matcher": ""
  }
],
"PostToolUse": [
  {
    "hooks": [{"type": "command", "command": "python3 /Users/kochunlong/.mission-control/hooks/mc-posttool-hook.py"}],
    "matcher": ""
  }
]
```

- [ ] **Step 2: Build, launch, and test with socket**

```bash
pkill -f "MissionControl.app" 2>/dev/null; sleep 1
open MissionControl/build/Build/Products/Release/MissionControl.app
sleep 2

python3 -c "
import socket, json, time
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect('$HOME/.mission-control/mc.sock')

# Register agent
sock.sendall((json.dumps({
    'type': 'status_update',
    'agent_id': 'perm_e2e',
    'name': 'E2E Test',
    'status': 'running',
    'task': 'Testing permission card',
    'tmux_session': 'main',
    'tmux_window': 0,
    'tmux_pane': 0
}) + '\n').encode())
time.sleep(1)

# Send permission request
sock.sendall((json.dumps({
    'type': 'permission_request',
    'agent_id': 'perm_e2e',
    'request_id': 'perm_001',
    'tool': 'Bash',
    'tool_input': {'command': 'echo hello world', 'description': 'Test command'},
    'tmux_session': 'main',
    'tmux_window': 0,
    'tmux_pane': 0
}) + '\n').encode())
print('Permission card should appear in MC')
time.sleep(10)

# Simulate PostToolUse → card should dismiss
sock.sendall((json.dumps({
    'type': 'question_resolved',
    'agent_id': 'perm_e2e'
}) + '\n').encode())
print('Card should dismiss')
sock.close()
"
```

Expected: Permission card appears with "Bash" tool, `$ echo hello world`, Allow/Deny buttons. After 10s the card auto-dismisses.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: inline permission approval — end-to-end wiring"
```

- [ ] **Step 4: Push**

```bash
git push origin main
```
