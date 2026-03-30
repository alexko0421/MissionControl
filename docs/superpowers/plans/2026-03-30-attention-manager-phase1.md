# MissionControl Phase 1: 主动注意力管理器

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform MissionControl from a passive dashboard into an active attention manager — pill flashes + sound when agents need you, global hotkey to toggle visibility, live terminal updates, and auto-cleanup of stale agents.

**Architecture:** All new features hook into the existing `AgentStore` (the single data source). Pill alert logic compares old vs new agent states on each `loadFromFile()`. Terminal polling uses a `Timer` that calls `TMuxBridge.capturePane()` every 5 seconds. Global hotkey uses `NSEvent.addGlobalMonitorForEvents`. No new files created — all changes go into existing files.

**Tech Stack:** SwiftUI, AppKit (NSPanel, NSEvent, NSSound), existing AgentStore/TMuxBridge

---

## File Structure

| File | Action | Changes |
|------|--------|---------|
| `MissionControl/AgentStore.swift` | **Modify** | Add: old agent state tracking, alert detection, terminal polling timer, agent cleanup |
| `MissionControl/ContentView.swift` | **Modify** | Add: pill flash animation when alert fires, alert state binding |
| `MissionControl/MissionControlApp.swift` | **Modify** | Add: global hotkey monitor registration on launch |
| `MissionControl/SharedComponents.swift` | **Modify** | Add: AlertPulse modifier for CapsuleBar flash effect |
| `mc-update.sh` | **Modify** | Fix: shell injection via proper JSON escaping |
| `scripts/mc-hook.py` | **Keep** | No changes (already works) |

---

### Task 1: Agent Alert Detection in AgentStore

**Files:**
- Modify: `MissionControl/AgentStore.swift`

The core logic: when `loadFromFile()` runs, compare old agent statuses to new ones. If any agent just became `blocked` or `done`, fire an alert.

- [ ] **Step 1: Add alert state properties to AgentStore**

Add these properties after the existing `@Published var viewState` (line 20):

```swift
// Alert state — drives pill flash + sound
@Published var activeAlert: AgentAlert? = nil

struct AgentAlert: Equatable {
    let agentId: String
    let agentName: String
    let newStatus: AgentStatus
    let task: String
}

// Track previous agent statuses for diff
private var previousStatuses: [String: AgentStatus] = [:]

// Debounce: don't re-alert same agent within 5 seconds
private var lastAlertTimes: [String: Date] = [:]
```

- [ ] **Step 2: Add alert detection to loadFromFile()**

Replace the existing `loadFromFile()` method (lines 46-59) with:

```swift
func loadFromFile() {
    guard FileManager.default.fileExists(atPath: statusFile.path) else { return }
    do {
        let data = try Data(contentsOf: statusFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([Agent].self, from: data)

        // Detect status changes before updating agents
        let now = Date()
        for agent in loaded {
            let oldStatus = previousStatuses[agent.id]
            let isNewBlockedOrDone = (agent.status == .blocked || agent.status == .done)
            let statusChanged = (oldStatus != nil && oldStatus != agent.status)
            let isFirstAppearanceBlocked = (oldStatus == nil && agent.status == .blocked)

            if (statusChanged || isFirstAppearanceBlocked) && isNewBlockedOrDone {
                // Debounce check: skip if alerted within last 5 seconds
                if let lastAlert = lastAlertTimes[agent.id],
                   now.timeIntervalSince(lastAlert) < 5 {
                    continue
                }
                lastAlertTimes[agent.id] = now
                activeAlert = AgentAlert(
                    agentId: agent.id,
                    agentName: agent.name,
                    newStatus: agent.status,
                    task: agent.task
                )
                // Play alert sound
                NSSound(named: "Ping")?.play()
            }
        }

        // Update previous statuses
        previousStatuses = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.status) })

        withAnimation(.easeInOut(duration: 0.2)) {
            self.agents = loaded
        }
    } catch {
        print("AgentStore: failed to load status.json — \(error)")
    }
}
```

- [ ] **Step 3: Add `import AppKit` at top of AgentStore.swift**

Add after `import Combine` (line 3):

```swift
import AppKit
```

This is needed for `NSSound`.

- [ ] **Step 4: Add method to dismiss alert**

Add after the `viewStateKey` computed property (line 186):

```swift
func dismissAlert() {
    withAnimation(.easeOut(duration: 0.3)) {
        activeAlert = nil
    }
}
```

- [ ] **Step 5: Build and verify**

Run: `cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl" && xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add MissionControl/AgentStore.swift
git commit -m "feat: add agent alert detection with sound and debounce"
```

---

### Task 2: Pill Flash Animation in CapsuleBar

**Files:**
- Modify: `MissionControl/ContentView.swift`
- Modify: `MissionControl/SharedComponents.swift`

When `activeAlert` fires, the CapsuleBar flashes orange 3 times then auto-dismisses after 4 seconds.

- [ ] **Step 1: Add AlertPulse view modifier to SharedComponents.swift**

Add at the end of `SharedComponents.swift` (after `StatusBadge`):

```swift
// MARK: - Alert Pulse Modifier

struct AlertPulseModifier: ViewModifier {
    let isActive: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 100)
                    .stroke(Color(red: 0.937, green: 0.624, blue: 0.153), lineWidth: pulse ? 2 : 0)
                    .opacity(pulse ? 0.8 : 0)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .animation(
                        isActive ? .easeInOut(duration: 0.5).repeatCount(6, autoreverses: true) : .default,
                        value: pulse
                    )
            )
            .onChange(of: isActive) { newValue in
                if newValue {
                    pulse = true
                } else {
                    pulse = false
                }
            }
    }
}

extension View {
    func alertPulse(isActive: Bool) -> some View {
        modifier(AlertPulseModifier(isActive: isActive))
    }
}
```

- [ ] **Step 2: Add alert flash to CapsuleBar in ContentView.swift**

In `CapsuleBar`, find the outer `HStack` closing at line 161-166. Replace the modifiers on the right capsule (the `HStack` with `.padding(.horizontal, 8)` starting around line 150) by adding the alert pulse. Find this block (around line 155-159):

```swift
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .animation(.spring(response: 0.55, dampingFraction: 0.9), value: store.priorityAgent?.id)
```

Add right after it:

```swift
            .alertPulse(isActive: store.activeAlert != nil)
```

- [ ] **Step 3: Add auto-dismiss timer for alert**

In the `CapsuleBar` struct, add an `onReceive` modifier. Find the closing of the CapsuleBar body (line 165 `.environment(\.colorScheme, .dark)`). Add right before it:

```swift
        .onChange(of: store.activeAlert) { newAlert in
            if newAlert != nil {
                // Auto-dismiss after 4 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    store.dismissAlert()
                }
            }
        }
```

- [ ] **Step 4: Build and verify**

Run: `cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl" && xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Manual test**

1. Run the app
2. Manually edit `~/.mission-control/status.json` — change an agent's status to `"blocked"`
3. Expected: CapsuleBar flashes orange 3 times, you hear a "Ping" sound
4. After 4 seconds, the flash stops

- [ ] **Step 6: Commit**

```bash
git add MissionControl/ContentView.swift MissionControl/SharedComponents.swift
git commit -m "feat: add pill flash animation when agent needs attention"
```

---

### Task 3: Terminal Polling Timer

**Files:**
- Modify: `MissionControl/AgentStore.swift`

Add a 5-second timer that calls `TMuxBridge.capturePane()` for each running agent with a tmux target.

- [ ] **Step 1: Add polling timer properties to AgentStore**

Add after the `private var fileSource` property (around line 25):

```swift
private var pollingTimer: Timer?
```

- [ ] **Step 2: Add startPolling and stopPolling methods**

Add after the `stopWatching()` method (around line 37):

```swift
private func startPolling() {
    pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
        Task { @MainActor in
            self?.pollTerminals()
        }
    }
}

private func stopPolling() {
    pollingTimer?.invalidate()
    pollingTimer = nil
}

private func pollTerminals() {
    for i in agents.indices {
        guard agents[i].status == .running,
              let target = agents[i].tmuxTarget else { continue }
        Task.detached { [target] in
            let lines = TMuxBridge.capturePane(target: target)
            await MainActor.run { [weak self, lines] in
                guard let self = self,
                      let idx = self.agents.firstIndex(where: { $0.tmuxTarget == target }) else { return }
                if !lines.isEmpty {
                    self.agents[idx].terminalLines = lines
                    self.agents[idx].updatedAt = Date()
                }
            }
        }
    }
}
```

- [ ] **Step 3: Start polling in startWatching()**

In `startWatching()` (line 29-33), add `startPolling()` call:

```swift
func startWatching() {
    createStatusDirIfNeeded()
    loadFromFile()
    startFileWatcher()
    startPolling()
}
```

- [ ] **Step 4: Stop polling in stopWatching()**

Update `stopWatching()`:

```swift
func stopWatching() {
    fileSource?.cancel()
    fileSource = nil
    stopPolling()
}
```

- [ ] **Step 5: Build and verify**

Run: `cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl" && xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add MissionControl/AgentStore.swift
git commit -m "feat: add 5-second terminal polling timer for live output"
```

---

### Task 4: Auto-Cleanup of Stale Agents

**Files:**
- Modify: `MissionControl/AgentStore.swift`

Remove done agents older than 1 hour and idle agents older than 24 hours. Run cleanup on each `loadFromFile()`. Don't remove an agent the user is currently viewing.

- [ ] **Step 1: Add cleanup method to AgentStore**

Add after `pollTerminals()`:

```swift
private func cleanupStaleAgents() {
    let now = Date()
    let viewingAgentId: String? = {
        if case .summary(let id) = viewState { return id }
        return nil
    }()

    agents.removeAll { agent in
        // Don't remove agent user is currently viewing
        if agent.id == viewingAgentId { return false }

        let age = now.timeIntervalSince(agent.updatedAt)
        switch agent.status {
        case .done:  return age > 3600      // 1 hour
        case .idle:  return age > 86400     // 24 hours
        default:     return false
        }
    }
}
```

- [ ] **Step 2: Call cleanup in loadFromFile()**

In `loadFromFile()`, add `cleanupStaleAgents()` right after `self.agents = loaded` (inside the `withAnimation` closure):

```swift
withAnimation(.easeInOut(duration: 0.2)) {
    self.agents = loaded
}
cleanupStaleAgents()
```

Note: cleanup runs after loading so we clean the freshly loaded data. Changes won't be saved back to status.json — only the in-memory view is cleaned. This is intentional: the daemon/hook owns the file.

- [ ] **Step 3: Build and verify**

Run: `cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl" && xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add MissionControl/AgentStore.swift
git commit -m "feat: auto-cleanup stale done/idle agents from view"
```

---

### Task 5: Global Hotkey to Toggle Panel

**Files:**
- Modify: `MissionControl/MissionControlApp.swift`

Register `NSEvent.addGlobalMonitorForEvents` on launch. When the stored hotkey combo is pressed, toggle the FloatingPanel visibility.

- [ ] **Step 1: Add hotkey monitor to AppDelegate**

Replace the entire `MissionControlApp.swift` content with:

```swift
import SwiftUI

@main
struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var store = AgentStore()
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the floating panel
        let contentRect = NSRect(x: 0, y: 0, width: 10, height: 10)
        panel = FloatingPanel(contentRect: contentRect)

        let hostingView = NSHostingView(rootView:
            ContentView()
                .environmentObject(store)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        // Position near top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 200
            let y = screenFrame.maxY - 45
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()

        // Start data watching
        store.startWatching()

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Register global hotkey
        registerGlobalHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopWatching()
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Global Hotkey

    private func registerGlobalHotkey() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let stored = UserDefaults.standard.string(forKey: "globalHotkey") ?? "⌥ + Space"
            if self.eventMatchesHotkey(event, hotkey: stored) {
                Task { @MainActor in
                    self.togglePanel()
                }
            }
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func eventMatchesHotkey(_ event: NSEvent, hotkey: String) -> Bool {
        // Parse stored hotkey string like "⌥ + Space" or "⌘ + ⇧ + M"
        let parts = hotkey.components(separatedBy: " + ").map { $0.trimmingCharacters(in: .whitespaces) }

        var requiredModifiers: NSEvent.ModifierFlags = []
        var requiredKey: String?

        for part in parts {
            switch part {
            case "⌃": requiredModifiers.insert(.control)
            case "⌥": requiredModifiers.insert(.option)
            case "⇧": requiredModifiers.insert(.shift)
            case "⌘": requiredModifiers.insert(.command)
            case "Space": requiredKey = " "
            case "Enter": requiredKey = "\r"
            default: requiredKey = part.lowercased()
            }
        }

        // Check modifiers match (only the ones we care about)
        let relevantFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let eventMods = event.modifierFlags.intersection(relevantFlags)
        guard eventMods == requiredModifiers else { return false }

        // Check key matches
        if let key = requiredKey {
            let eventKey = event.keyCode == 49 ? " " :
                           event.keyCode == 36 ? "\r" :
                           (event.charactersIgnoringModifiers?.lowercased() ?? "")
            return eventKey == key
        }

        return false
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl" && xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manual test**

1. Run the app
2. Go to Settings > Hotkeys, set a hotkey (e.g., ⌥ + Space)
3. Switch to another app
4. Press the hotkey
5. Expected: MissionControl panel appears/disappears
6. Note: macOS may prompt for Accessibility permission on first use

- [ ] **Step 4: Commit**

```bash
git add MissionControl/MissionControlApp.swift
git commit -m "feat: add global hotkey to toggle floating panel visibility"
```

---

### Task 6: Fix mc-update.sh Shell Injection

**Files:**
- Modify: `mc-update.sh`

Replace inline Python string interpolation with proper `sys.argv` and `json.dumps()`.

- [ ] **Step 1: Rewrite mc-update.sh**

Replace the entire file content:

```bash
#!/bin/zsh
# mc-update.sh — call this from your Claude Code sessions to update Mission Control
# Usage: mc-update.sh <agent-id> <status> <task> <summary> <next-action> [tmux-session] [tmux-window] [tmux-pane]
#
# Status values: running | blocked | done | idle

STATUS_DIR="$HOME/.mission-control"
STATUS_FILE="$STATUS_DIR/status.json"
mkdir -p "$STATUS_DIR"

ID="${1:-unknown}"
STATUS="${2:-running}"
TASK="${3:-進行中...}"
SUMMARY="${4:-}"
NEXT="${5:-}"
TMUX_SESSION="${6:-}"
TMUX_WINDOW="${7:-0}"
TMUX_PANE="${8:-0}"

python3 - "$ID" "$STATUS" "$TASK" "$SUMMARY" "$NEXT" "$TMUX_SESSION" "$TMUX_WINDOW" "$TMUX_PANE" "$STATUS_FILE" << 'PYEOF'
import json, sys, os
from datetime import datetime, timezone

agent_id = sys.argv[1]
status = sys.argv[2]
task = sys.argv[3]
summary = sys.argv[4]
next_action = sys.argv[5]
tmux_session = sys.argv[6] if sys.argv[6] else None
tmux_window = int(sys.argv[7])
tmux_pane = int(sys.argv[8])
status_file = sys.argv[9]

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# Load existing agents
agents = []
if os.path.exists(status_file):
    try:
        with open(status_file) as f:
            agents = json.load(f)
    except (json.JSONDecodeError, IOError):
        agents = []

# Remove existing entry for this agent
agents = [a for a in agents if a.get("id") != agent_id]

# Add new entry
agents.append({
    "id": agent_id,
    "name": agent_id,
    "status": status,
    "task": task,
    "summary": summary,
    "terminalLines": [],
    "nextAction": next_action,
    "updatedAt": now,
    "worktree": agent_id,
    "tmuxSession": tmux_session,
    "tmuxWindow": tmux_window,
    "tmuxPane": tmux_pane,
})

with open(status_file, "w") as f:
    json.dump(agents, f, ensure_ascii=False, indent=2)

print(f"✓ Mission Control updated: {agent_id} → {status}")
PYEOF
```

- [ ] **Step 2: Verify the script works**

Run:
```bash
cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl"
bash mc-update.sh "test-agent" "running" "Test task with 'quotes' and \"doubles\"" "Summary" "Next"
cat ~/.mission-control/status.json | python3 -m json.tool | head -20
```

Expected: Valid JSON with the test agent, no parse errors.

- [ ] **Step 3: Clean up test data**

```bash
python3 -c "
import json
f = open('$HOME/.mission-control/status.json')
agents = json.load(f)
agents = [a for a in agents if a['id'] != 'test-agent']
with open('$HOME/.mission-control/status.json', 'w') as out:
    json.dump(agents, out, ensure_ascii=False, indent=2)
"
```

- [ ] **Step 4: Commit**

```bash
git add mc-update.sh
git commit -m "fix: replace shell string interpolation with safe sys.argv JSON handling"
```

---

### Task 7: Configure Claude Code Hook

**Files:**
- No code changes — configuration only

Set up `~/.claude/settings.json` to call `mc-hook.py` after each Claude response.

- [ ] **Step 1: Check current Claude Code settings**

Run:
```bash
cat ~/.claude/settings.json 2>/dev/null || echo "{}"
```

- [ ] **Step 2: Add the hook configuration**

The hook should call `mc-hook.py` (single run mode, not daemon) after each assistant response. The exact configuration depends on the current settings file content.

Add to `~/.claude/settings.json` under the `"hooks"` key:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "command": "python3 /Users/kochunlong/Library/Mobile\\ Documents/com~apple~CloudDocs/MissionControl/scripts/mc-hook.py"
      }
    ]
  }
}
```

Note: If there's already a `hooks` section, merge this into it rather than replacing.

- [ ] **Step 3: Verify the hook path is correct**

Run:
```bash
python3 "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl/scripts/mc-hook.py" 2>&1 | head -3
```

Expected: Script runs without error (may print nothing if no active projects found).

- [ ] **Step 4: Commit**

No code to commit — this is a local configuration change. Note in a README or docs that users need to configure this hook.

---

### Task 8: Integration Test — Full Flow

**Files:**
- None (manual testing)

- [ ] **Step 1: Start the app**

Build and run from Xcode, or:
```bash
cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl"
xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build
open build/Release/MissionControl.app
```

- [ ] **Step 2: Test alert detection**

```bash
~/.mission-control/mc-update.sh "test-1" "running" "Testing alert" "Running a test" "Wait for it"
sleep 2
~/.mission-control/mc-update.sh "test-1" "blocked" "Need your input" "Agent blocked" "Choose A or B"
```

Expected:
- CapsuleBar flashes orange
- You hear a "Ping" sound
- After 4 seconds, flash stops

- [ ] **Step 3: Test debounce**

```bash
~/.mission-control/mc-update.sh "test-1" "running" "Running again" "Brief run" "Wait"
sleep 1
~/.mission-control/mc-update.sh "test-1" "blocked" "Blocked again" "Within 5 seconds" "Choose"
```

Expected: No alert (within 5-second debounce window)

- [ ] **Step 4: Test global hotkey**

1. Switch to another app (e.g., Terminal)
2. Press your configured hotkey (default: ⌥ + Space)
3. Expected: Panel hides
4. Press again
5. Expected: Panel shows

- [ ] **Step 5: Test terminal polling**

1. Open a tmux session: `tmux new -s test-mc`
2. Update status with tmux target:
```bash
~/.mission-control/mc-update.sh "tmux-test" "running" "Testing polling" "Running in tmux" "Watch terminal" "test-mc" 0 0
```
3. Type commands in the tmux session
4. Expected: Terminal output appears in MissionControl within 5 seconds

- [ ] **Step 6: Test auto-cleanup**

```bash
# Create a done agent with old timestamp
python3 -c "
import json, os
f = os.path.expanduser('~/.mission-control/status.json')
agents = json.load(open(f))
agents.append({
    'id': 'old-done',
    'name': 'Old Done Agent',
    'status': 'done',
    'task': 'Finished long ago',
    'summary': '',
    'terminalLines': [],
    'nextAction': '',
    'updatedAt': '2026-03-29T00:00:00Z',
    'worktree': None,
    'tmuxSession': None,
    'tmuxWindow': 0,
    'tmuxPane': 0
})
json.dump(agents, open(f, 'w'), ensure_ascii=False, indent=2)
"
```

Expected: After the file watcher triggers, the "Old Done Agent" should not appear in the session list (cleaned up because done > 1 hour).

- [ ] **Step 7: Clean up test data**

```bash
python3 -c "
import json, os
f = os.path.expanduser('~/.mission-control/status.json')
agents = json.load(open(f))
agents = [a for a in agents if a['id'] not in ('test-1', 'tmux-test', 'old-done')]
json.dump(agents, open(f, 'w'), ensure_ascii=False, indent=2)
"
tmux kill-session -t test-mc 2>/dev/null
```

- [ ] **Step 8: Final commit if any tweaks were needed**

```bash
git add -A
git status
# Only commit if there are changes
git commit -m "feat: MissionControl Phase 1 — active attention manager"
```
