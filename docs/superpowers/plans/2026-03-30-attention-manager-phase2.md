# MissionControl Phase 2: Focus Mode + 认知负荷指示器

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Focus Mode (lock onto one agent, silence other alerts) and a cognitive load indicator (visual warning when too many agents are running) to complete the active attention management system.

**Architecture:** Focus Mode adds a `focusedAgentId` to AgentStore, persisted via `@AppStorage`. Alert logic checks focus state before firing. Cognitive load indicator is a small colored bar in CapsuleBar that changes color based on running agent count. Both features hook into existing AgentStore and CapsuleBar — no new files.

**Tech Stack:** SwiftUI, existing AgentStore/CapsuleBar

---

## File Structure

| File | Action | Changes |
|------|--------|---------|
| `MissionControl/AgentStore.swift` | **Modify** | Add focusedAgentId, focus methods, modify alert logic to respect focus |
| `MissionControl/ContentView.swift` | **Modify** | Add focus indicator to CapsuleBar, long-press to focus in SessionRow, cognitive load bar |

---

### Task 1: Focus Mode State in AgentStore

**Files:**
- Modify: `MissionControl/AgentStore.swift`

- [ ] **Step 1: Add focus state properties**

Add after `private var lastAlertTimes: [String: Date] = [:]` (line 37):

```swift
// Focus Mode — lock onto one agent, silence other alerts
@AppStorage("focusedAgentId") var focusedAgentId: String = ""

var isFocusModeActive: Bool { !focusedAgentId.isEmpty }

var focusedAgent: Agent? {
    guard isFocusModeActive else { return nil }
    return agents.first { $0.id == focusedAgentId }
}
```

- [ ] **Step 2: Add focus mode methods**

Add after `dismissAlert()` (line 294):

```swift
func startFocus(agentId: String) {
    withAnimation(.easeInOut(duration: 0.2)) {
        focusedAgentId = agentId
    }
}

func stopFocus() {
    withAnimation(.easeInOut(duration: 0.2)) {
        focusedAgentId = ""
    }
}
```

- [ ] **Step 3: Modify alert logic to respect focus mode**

In `loadFromFile()`, find the alert firing block (around line 133-148). Replace:

```swift
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
```

With:

```swift
                if (statusChanged || isFirstAppearanceBlocked) && isNewBlockedOrDone {
                    // Debounce check: skip if alerted within last 5 seconds
                    if let lastAlert = lastAlertTimes[agent.id],
                       now.timeIntervalSince(lastAlert) < 5 {
                        continue
                    }
                    // Focus mode: only alert for focused agent (or all if no focus)
                    if isFocusModeActive && agent.id != focusedAgentId {
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
```

- [ ] **Step 4: Auto-exit focus when focused agent completes**

In `loadFromFile()`, add after the `cleanupStaleAgents()` call (line 157):

```swift
// Auto-exit focus if focused agent is done
if isFocusModeActive {
    if let focused = agents.first(where: { $0.id == focusedAgentId }) {
        if focused.status == .done {
            stopFocus()
        }
    } else {
        // Focused agent no longer exists
        stopFocus()
    }
}
```

- [ ] **Step 5: Build and verify**

Run: `cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl" && xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add MissionControl/AgentStore.swift
git commit -m "feat: add Focus Mode state — lock onto agent, silence other alerts, auto-exit on done"
```

---

### Task 2: Focus Mode UI in CapsuleBar and SessionList

**Files:**
- Modify: `MissionControl/ContentView.swift`

- [ ] **Step 1: Add focus indicator to CapsuleBar**

In CapsuleBar, find the inner pill `HStack` that shows agent name (around line 100-114). After the existing `StatusDot` and agent name, add a focus icon. Replace:

```swift
                    HStack(spacing: 4) {
                        StatusDot(status: agent.status)
                        Text(agent.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
```

With:

```swift
                    HStack(spacing: 4) {
                        StatusDot(status: agent.status)
                        Text(agent.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if store.isFocusModeActive && store.focusedAgentId == agent.id {
                            Image(systemName: "scope")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
```

- [ ] **Step 2: Add tap on focus indicator to exit focus**

In CapsuleBar, find `.environment(\.colorScheme, .dark)` (line 173). Add right before it:

```swift
        .onTapGesture {
            if store.isFocusModeActive {
                store.stopFocus()
            }
        }
```

- [ ] **Step 3: Add long-press to SessionRow for entering focus**

In `SessionRow` (around line 255), find `.onHover { isHovered = $0 }` (line 298). Add right after it:

```swift
        .onLongPressGesture(minimumDuration: 0.5) {
            store.startFocus(agentId: agent.id)
        }
```

Note: SessionRow needs access to `store`. Add `@EnvironmentObject var store: AgentStore` property to SessionRow, right after the existing `let agent: Agent`.

- [ ] **Step 4: Show focus badge in SessionRow**

In SessionRow's HStack, after the status badge `Text(agent.status.label)` block (around line 277-283), add:

```swift
            if store.isFocusModeActive && store.focusedAgentId == agent.id {
                Image(systemName: "scope")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.365, green: 0.792, blue: 0.647))
            }
```

- [ ] **Step 5: Build and verify**

Run: `cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl" && xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Manual test**

1. Run the app with 2+ agents
2. Long-press an agent in session list → 🎯 scope icon appears
3. CapsuleBar shows scope icon next to focused agent name
4. Trigger a blocked alert on a NON-focused agent → no alert
5. Trigger a blocked alert on the focused agent → alert fires
6. Tap CapsuleBar → exits focus mode
7. Change focused agent to done → auto-exits focus

- [ ] **Step 7: Commit**

```bash
git add MissionControl/ContentView.swift
git commit -m "feat: add Focus Mode UI — scope icon, long-press to focus, tap to exit"
```

---

### Task 3: Cognitive Load Indicator

**Files:**
- Modify: `MissionControl/ContentView.swift`

A small colored bar at the bottom edge of the CapsuleBar that shows cognitive load: green (1-2 running), yellow (3-4), red (5+).

- [ ] **Step 1: Add CognitiveLoadBar view**

Add right before the `// MARK: - Session List Panel` comment (around line 177):

```swift
// MARK: - Cognitive Load Bar

struct CognitiveLoadBar: View {
    let runningCount: Int

    private var loadColor: Color {
        switch runningCount {
        case 0:     return .clear
        case 1...2: return Color(red: 0.365, green: 0.792, blue: 0.647) // green
        case 3...4: return Color(red: 0.937, green: 0.624, blue: 0.153) // yellow/orange
        default:    return Color(red: 0.886, green: 0.294, blue: 0.290) // red
        }
    }

    private var loadText: String {
        switch runningCount {
        case 0:     return ""
        case 1...2: return "\(runningCount) agent"
        case 3...4: return "⚠ \(runningCount) agents"
        default:    return "🔴 \(runningCount) agents"
        }
    }

    var body: some View {
        if runningCount > 0 {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(loadColor)
                    .frame(width: CGFloat(min(runningCount, 6)) * 12, height: 3)
                    .animation(.easeInOut(duration: 0.3), value: runningCount)

                if runningCount >= 3 {
                    Text(loadText)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(loadColor)
                }

                Spacer()
            }
            .padding(.horizontal, 54) // align with capsule content
            .padding(.bottom, 2)
            .environment(\.colorScheme, .dark)
        }
    }
}
```

- [ ] **Step 2: Add CognitiveLoadBar to ContentView**

In ContentView's body, find `CapsuleBar()` (line 9). Add the load bar right after it:

```swift
            CapsuleBar()
                .zIndex(2)

            CognitiveLoadBar(runningCount: store.runningCount)
                .zIndex(2)
```

- [ ] **Step 3: Build and verify**

Run: `cd "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl" && xcodebuild -project MissionControl.xcodeproj -scheme MissionControl build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Manual test**

1. Add 1-2 running agents → green bar
2. Add 3-4 running agents → yellow bar with "⚠ 3 agents"
3. Add 5+ running agents → red bar with "🔴 5 agents"
4. Remove agents → bar shrinks/disappears

Test with:
```bash
for i in 1 2 3 4 5; do
  ~/.mission-control/mc-update.sh "test-$i" "running" "Task $i" "Running" "Continue"
done
```

Clean up:
```bash
for i in 1 2 3 4 5; do
  ~/.mission-control/mc-update.sh "test-$i" "done" "Done $i" "Finished" ""
done
```

- [ ] **Step 5: Commit**

```bash
git add MissionControl/ContentView.swift
git commit -m "feat: add cognitive load indicator — green/yellow/red bar based on running agent count"
```
