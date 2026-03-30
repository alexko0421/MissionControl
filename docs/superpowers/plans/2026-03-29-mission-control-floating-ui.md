# Mission Control Floating UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Mission Control as a floating NSPanel with three states: Terminal View (default), Session List (overlay), and Summary View.

**Architecture:** Replace the current WindowGroup + sidebar/list toggle with an NSPanel-based floating window. The app has three visual states managed by a simple enum. The data layer (AgentStore, TMuxBridge, Models) stays largely intact — the main changes are in the view layer and app entry point.

**Tech Stack:** SwiftUI, AppKit (NSPanel), existing TMuxBridge/AgentStore

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `MissionControlApp.swift` | **Rewrite** | NSPanel setup, app lifecycle, menu bar presence |
| `FloatingPanel.swift` | **Create** | NSPanel subclass — always-on-top, semi-transparent, draggable |
| `ContentView.swift` | **Rewrite** | State machine for three views, ☰ button, overlay logic |
| `TerminalView.swift` | **Create** | Full-screen live terminal output of priority agent |
| `SessionListOverlay.swift` | **Create** | Overlay with capsule-shaped session cards, sorted by priority |
| `SummaryView.swift` | **Create** | Full-screen summary of selected agent with ← back |
| `AgentStore.swift` | **Modify** | Add `priorityAgent` computed property, `sortedAgents`, view state enum |
| `Models.swift` | **Keep** | No changes needed |
| `TMuxBridge.swift` | **Keep** | No changes needed |
| `AgentListView.swift` | **Delete** | Replaced by SessionListOverlay |
| `AgentDetailView.swift` | **Delete** | Replaced by TerminalView + SummaryView |

---

### Task 1: Create FloatingPanel NSPanel subclass

**Files:**
- Create: `MissionControl/FloatingPanel.swift`

- [ ] **Step 1: Create FloatingPanel.swift**

```swift
import AppKit

class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Always on top
        level = .floating
        isFloatingPanel = true

        // Transparent titlebar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Semi-transparent background
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)

        // Allow interaction without activating the app
        hidesOnDeactivate = false

        // Remember position
        isMovableByWindowBackground = true

        // Min size
        minSize = NSSize(width: 360, height: 280)
    }
}
```

- [ ] **Step 2: Build and verify it compiles**

Run: `cd /tmp/MissionControl_preview/MissionControl && xcodebuild -scheme MissionControl build 2>&1 | tail -5`
Expected: Build may fail since we haven't integrated yet, but the file itself should have no syntax errors.

- [ ] **Step 3: Commit**

```bash
git add MissionControl/FloatingPanel.swift
git commit -m "feat: add FloatingPanel NSPanel subclass for always-on-top floating window"
```

---

### Task 2: Add view state and priority agent logic to AgentStore

**Files:**
- Modify: `MissionControl/AgentStore.swift`

- [ ] **Step 1: Add ViewState enum and new properties to AgentStore**

Add at the top of AgentStore class, after the existing `@Published` properties:

```swift
enum ViewState {
    case terminal
    case sessionList
    case summary(agentId: String)
}

@Published var viewState: ViewState = .terminal
```

- [ ] **Step 2: Add priorityAgent computed property**

Add after the existing `selectedAgent` computed property:

```swift
var priorityAgent: Agent? {
    // 1. First blocked agent (most recent)
    if let blocked = agents
        .filter({ $0.status == .blocked })
        .sorted(by: { $0.updatedAt > $1.updatedAt })
        .first {
        return blocked
    }
    // 2. Running agent with most recent output
    if let running = agents
        .filter({ $0.status == .running })
        .sorted(by: { $0.updatedAt > $1.updatedAt })
        .first {
        return running
    }
    // 3. Most recently updated agent
    return agents.sorted(by: { $0.updatedAt > $1.updatedAt }).first
}
```

- [ ] **Step 3: Add sortedAgents computed property**

Add after `priorityAgent`:

```swift
var sortedAgents: [Agent] {
    agents.sorted { a, b in
        let order: [AgentStatus] = [.blocked, .running, .done, .idle]
        let ai = order.firstIndex(of: a.status) ?? 99
        let bi = order.firstIndex(of: b.status) ?? 99
        if ai != bi { return ai < bi }
        return a.updatedAt > b.updatedAt
    }
}
```

- [ ] **Step 4: Add navigation helpers**

Add after `sortedAgents`:

```swift
func showTerminal() {
    withAnimation(.easeInOut(duration: 0.18)) {
        viewState = .terminal
    }
}

func showSessionList() {
    withAnimation(.easeInOut(duration: 0.18)) {
        viewState = .sessionList
    }
}

func showSummary(for agentId: String) {
    withAnimation(.easeInOut(duration: 0.18)) {
        viewState = .summary(agentId: agentId)
    }
}

func toggleSessionList() {
    switch viewState {
    case .sessionList:
        showTerminal()
    default:
        showSessionList()
    }
}

var summaryAgent: Agent? {
    if case .summary(let id) = viewState {
        return agents.first { $0.id == id }
    }
    return nil
}
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -scheme MissionControl build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (or warnings only — existing views still reference old properties, that's OK for now)

- [ ] **Step 6: Commit**

```bash
git add MissionControl/AgentStore.swift
git commit -m "feat: add view state machine, priority agent, and sorted agents to AgentStore"
```

---

### Task 3: Create TerminalView

**Files:**
- Create: `MissionControl/TerminalView.swift`

- [ ] **Step 1: Create TerminalView.swift**

```swift
import SwiftUI

struct TerminalView: View {
    let agent: Agent
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with ☰ button and agent info
            HStack(spacing: 10) {
                Button(action: { store.toggleSessionList() }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                StatusDot(status: agent.status)

                Text(agent.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))

                StatusBadge(status: agent.status)

                Spacer()

                Text(agent.timeAgo)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(agent.terminalLines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(line.type.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 1)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)

                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: agent.terminalLines.count) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add MissionControl/TerminalView.swift
git commit -m "feat: add TerminalView for live terminal output display"
```

---

### Task 4: Create SessionListOverlay

**Files:**
- Create: `MissionControl/SessionListOverlay.swift`

- [ ] **Step 1: Create SessionListOverlay.swift**

```swift
import SwiftUI

struct SessionListOverlay: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        ZStack {
            // Dimmed backdrop — tap to dismiss
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { store.showTerminal() }

            // Session list card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("所有 Session")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                    Spacer()

                    // Stats
                    HStack(spacing: 12) {
                        StatPill(count: store.blockedCount, color: AgentStatus.blocked.color)
                        StatPill(count: store.runningCount, color: AgentStatus.running.color)
                        StatPill(count: store.doneCount, color: AgentStatus.done.color)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Agent list
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.sortedAgents) { agent in
                            SessionCard(agent: agent)
                                .onTapGesture {
                                    store.showSummary(for: agent.id)
                                }
                        }
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
            .padding(24)
        }
    }
}

struct SessionCard: View {
    let agent: Agent
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: agent.status)

            Text(agent.name)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)

            Spacer()

            Text(agent.timeAgo)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(isHovered ? 0.08 : 0.04))
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}

struct StatPill: View {
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add MissionControl/SessionListOverlay.swift
git commit -m "feat: add SessionListOverlay with sorted capsule cards"
```

---

### Task 5: Create SummaryView

**Files:**
- Create: `MissionControl/SummaryView.swift`

- [ ] **Step 1: Create SummaryView.swift**

```swift
import SwiftUI

struct SummaryView: View {
    let agent: Agent
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack(spacing: 10) {
                Button(action: { store.showTerminal() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("返回")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                StatusBadge(status: agent.status)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Summary content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Agent name
                    HStack(spacing: 10) {
                        StatusDot(status: agent.status)
                        Text(agent.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    // Task
                    SummarySection(label: "任務") {
                        Text(agent.task)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineSpacing(4)
                    }

                    // Summary
                    SummarySection(label: "最新摘要") {
                        Text(agent.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineSpacing(4)
                    }

                    // Next action
                    SummarySection(label: "下一步") {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AgentStatus.running.color)
                            Text(agent.nextAction)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.7))
                                .lineSpacing(4)
                        }
                    }

                    // Worktree info (if available)
                    if let worktree = agent.worktree {
                        SummarySection(label: "Worktree") {
                            Text(worktree)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.5))
                        }
                    }
                }
                .padding(18)
            }
        }
    }
}

struct SummarySection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))
                .textCase(.uppercase)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add MissionControl/SummaryView.swift
git commit -m "feat: add SummaryView showing agent task, summary, and next action"
```

---

### Task 6: Rewrite ContentView with state machine

**Files:**
- Modify: `MissionControl/ContentView.swift`

- [ ] **Step 1: Rewrite ContentView.swift**

Replace the entire file content with:

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        ZStack {
            // Base layer: Terminal or Summary
            Group {
                switch store.viewState {
                case .terminal, .sessionList:
                    if let agent = store.priorityAgent {
                        TerminalView(agent: agent)
                    } else {
                        emptyState
                    }
                case .summary(let agentId):
                    if let agent = store.agents.first(where: { $0.id == agentId }) {
                        SummaryView(agent: agent)
                    } else {
                        emptyState
                    }
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: store.viewStateKey)

            // Overlay layer: Session list
            if case .sessionList = store.viewState {
                SessionListOverlay()
                    .transition(.opacity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("未有 Session")
                .font(.system(size: 13))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Add viewStateKey to AgentStore for animation**

Add this computed property to AgentStore after the `summaryAgent` property:

```swift
var viewStateKey: String {
    switch viewState {
    case .terminal: return "terminal"
    case .sessionList: return "sessionList"
    case .summary(let id): return "summary-\(id)"
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add MissionControl/ContentView.swift MissionControl/AgentStore.swift
git commit -m "feat: rewrite ContentView with three-state view machine"
```

---

### Task 7: Rewrite MissionControlApp with NSPanel

**Files:**
- Modify: `MissionControl/MissionControlApp.swift`

- [ ] **Step 1: Rewrite MissionControlApp.swift**

Replace the entire file content with:

```swift
import SwiftUI

@main
struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty settings scene — the panel is managed by AppDelegate
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var store = AgentStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the floating panel
        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 400)
        panel = FloatingPanel(contentRect: contentRect)

        // Set SwiftUI content
        let contentView = ContentView()
            .environmentObject(store)

        panel.contentView = NSHostingView(rootView: contentView)

        // Center and show
        panel.center()
        panel.orderFrontRegardless()

        // Start data watching
        store.startWatching()

        // Hide dock icon — this is a floating utility
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopWatching()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add MissionControl/MissionControlApp.swift
git commit -m "feat: replace WindowGroup with NSPanel-based floating window"
```

---

### Task 8: Move reusable components and delete old views

**Files:**
- Delete: `MissionControl/AgentListView.swift`
- Delete: `MissionControl/AgentDetailView.swift`

- [ ] **Step 1: Identify reusable components still needed**

The following components from the old files are still referenced and need to stay available. They are already used in the new views:
- `StatusDot` (from AgentListView.swift) — used in TerminalView, SessionListOverlay, SummaryView
- `StatusBadge` (from AgentDetailView.swift) — used in TerminalView, SummaryView

- [ ] **Step 2: Create SharedComponents.swift with StatusDot and StatusBadge**

```swift
import SwiftUI

// MARK: - Status Dot

struct StatusDot: View {
    let status: AgentStatus
    @State private var pulse = false

    var body: some View {
        ZStack {
            if status.hasPulse {
                Circle()
                    .fill(status.color.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 0.6)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
        }
        .frame(width: 12, height: 12)
        .onAppear { if status.hasPulse { pulse = true } }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: AgentStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 10))
            .foregroundColor(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
```

- [ ] **Step 3: Delete old view files**

```bash
rm MissionControl/AgentListView.swift
rm MissionControl/AgentDetailView.swift
```

- [ ] **Step 4: Remove selectedAgentId and selectedAgent from AgentStore**

Remove these lines from AgentStore.swift:

```swift
// DELETE these:
@Published var selectedAgentId: String? = nil

var selectedAgent: Agent? {
    guard let id = selectedAgentId else { return nil }
    return agents.first { $0.id == id }
}
```

Also remove `runningCount`, `blockedCount`, `doneCount` computed properties from AgentStore and move them. Actually, they are still used in SessionListOverlay — keep them in AgentStore.

- [ ] **Step 5: Build the full project**

Run: `xcodebuild -scheme MissionControl build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add MissionControl/SharedComponents.swift
git add -u  # stages deletions and modifications
git commit -m "refactor: extract shared components, delete old list/detail views"
```

---

### Task 9: Remove hardcoded color scheme, follow system appearance

**Files:**
- Modify: `MissionControl/Models.swift` (update colors to be adaptive)

- [ ] **Step 1: Verify current color handling**

The current code uses hardcoded RGB colors (e.g., `Color(red: 0.365, green: 0.792, blue: 0.647)`). These status colors (green, orange, blue) work fine in both light and dark mode since they are accent colors, not background colors.

The new views use semantic colors (`.primary`, `.secondary`, `.ultraThinMaterial`) which automatically adapt to system appearance.

The old `preferredColorScheme(.dark)` was removed in Task 7 when we rewrote MissionControlApp.swift. No further changes needed.

- [ ] **Step 2: Verify TerminalLine colors work in light mode**

The `TerminalLine.LineType.color` uses hardcoded colors. Update them to work in both modes:

In `Models.swift`, replace the `LineType` color computed property:

```swift
var color: Color {
    switch self {
    case .normal:  return .primary.opacity(0.5)
    case .success: return Color(red: 0.365, green: 0.792, blue: 0.647)
    case .warning: return Color(red: 0.937, green: 0.624, blue: 0.153)
    case .error:   return Color(red: 0.886, green: 0.294, blue: 0.290)
    }
}
```

Only `.normal` changes — from hardcoded white to `.primary` which adapts to system appearance.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme MissionControl build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add MissionControl/Models.swift
git commit -m "fix: use adaptive colors for system dark/light mode support"
```

---

### Task 10: Final integration test and cleanup

**Files:**
- All files

- [ ] **Step 1: Verify all files are present and consistent**

Expected file list in `MissionControl/MissionControl/`:
- `MissionControlApp.swift` — NSPanel + AppDelegate
- `FloatingPanel.swift` — NSPanel subclass
- `ContentView.swift` — three-state view machine
- `TerminalView.swift` — live terminal output
- `SessionListOverlay.swift` — overlay session list
- `SummaryView.swift` — agent summary
- `SharedComponents.swift` — StatusDot, StatusBadge
- `AgentStore.swift` — data store with priority logic
- `Models.swift` — Agent, AgentStatus, TerminalLine
- `TMuxBridge.swift` — tmux CLI wrapper

Run: `ls MissionControl/MissionControl/*.swift | sort`

- [ ] **Step 2: Full clean build**

Run: `xcodebuild -scheme MissionControl clean build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run the app and verify the three states**

Run: `open -a MissionControl` or build and run from Xcode.

Manual verification checklist:
1. App launches as a floating panel (always on top, no dock icon)
2. Panel shows terminal output of the priority agent
3. Clicking ☰ shows session list overlay with dimmed backdrop
4. Clicking outside the overlay dismisses it
5. Clicking a session card shows its summary
6. Clicking ← in summary returns to terminal view
7. Session list is sorted: blocked > running > done > idle
8. Toggle system appearance (dark/light) — colors adapt correctly
9. Panel is draggable and resizable

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: Mission Control floating UI — complete rebuild as NSPanel with three-state navigation"
```
