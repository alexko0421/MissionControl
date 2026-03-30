# Mission Control — Floating UI Redesign

## Origin

> 瓶頸不在 AI 的 context window，在人的 context window。 — Zara Zhang

Mission Control is a **human context window management tool**. When running multiple parallel Claude Code sessions, the bottleneck is not AI capability — it's human attention fragmentation. Mission Control exists to answer one question at any moment: **which session matters most right now, and what should you do next?**

It is not a coding tool. It is not a task manager. It is a cognitive pressure valve.

## Architecture

### Window

- **NSPanel** (floating panel), always-on-top
- Semi-transparent background
- Draggable and resizable
- Follows system dark/light mode (no manual toggle)

### Three States

The app has exactly three visual states:

#### 1. Terminal View (Default)

Full-screen live terminal output of the **priority agent**.

**Priority agent selection logic:**
1. First blocked agent (sorted by most recent `updatedAt`)
2. If no blocked agents: the running agent with the most recent terminal output
3. If no running agents: the most recently updated agent regardless of status

Top-left corner: a `☰` button to open the session list overlay.

Terminal content is captured via `tmux capture-pane` every 5 seconds (last 30 lines). Lines are color-coded by type:
- **normal**: default text color
- **success**: green (detected by `✓`, "success", "passed", "done")
- **warning**: orange (detected by `⚠`, "warning", "await", "waiting")
- **error**: red (detected by `✗`, "error", "failed", "fatal")

#### 2. Session List (Overlay)

Triggered by tapping `☰`. Appears as an **overlay on top of the terminal view** (not a screen replacement). Terminal output remains visible behind the overlay (dimmed).

Dismiss by:
- Tapping outside the overlay
- Tapping `☰` again

**List contents:**
- Capsule-shaped session cards
- Each card shows: agent name + status color indicator
- Sort order: **blocked > running > done > idle**
- Within each status group: sorted by `updatedAt` (most recent first)

Tapping a session card navigates to its Summary view.

#### 3. Summary View (Full Replacement)

Replaces the terminal view entirely. Shows:
- **Agent name** and status badge
- **Task**: what this agent was created to do
- **Summary**: current state of the work
- **Next action**: what needs to happen next

Top-left: `←` button to return to Terminal View (which now shows this agent's terminal output, making it the selected agent).

## Data Flow

### Status Updates (Push)

```
Claude Code session
    ↓ calls
mc-update.sh <agent-id> <status> <task> <summary> <next-action> [session] [window] [pane]
    ↓ writes
~/.mission-control/status.json
    ↓ watched by
DispatchSource (file watcher) in AgentStore
    ↓ triggers
@Published agents: [Agent] update
    ↓ drives
SwiftUI views
```

### Terminal Output (Poll)

```
Timer (every 5 seconds)
    ↓
For each agent with status == .running AND valid tmuxTarget:
    TMuxBridge.capturePane(target, lastLines: 30)
    ↓
    Update agent.terminalLines
    Update agent.updatedAt
```

### Command Sending

```
User types in input field (if provided)
    ↓
TMuxBridge.sendKeys(target, command)
    ↓
tmux pane receives keystrokes
```

## Data Model

### AgentStatus

```swift
enum AgentStatus: String, Codable, CaseIterable {
    case running    // 進行中
    case blocked    // 需要你
    case done       // 已完成
    case idle       // 閒置
}
```

### Agent

```swift
struct Agent: Identifiable, Codable {
    var id: String
    var name: String
    var status: AgentStatus
    var task: String
    var summary: String
    var terminalLines: [TerminalLine]
    var nextAction: String
    var updatedAt: Date
    var worktree: String?
    var tmuxSession: String?
    var tmuxWindow: Int?
    var tmuxPane: Int?
}
```

### TerminalLine

```swift
struct TerminalLine: Codable, Identifiable {
    var id: UUID
    var text: String
    var type: LineType  // normal, success, warning, error
}
```

## TMuxBridge

Synchronous shell wrapper. Three operations:

| Method | tmux Command | Purpose |
|--------|-------------|---------|
| `capturePane(target, lastLines)` | `tmux capture-pane -t "{target}" -p -S -{lastLines}` | Read terminal output |
| `sendKeys(target, command)` | `tmux send-keys -t "{target}" "{command}" Enter` | Send command to pane |
| `listSessions()` | `tmux ls -F '#{session_name}'` | List active sessions |

## Localization

UI language: Traditional Chinese throughout.

| Key | Label |
|-----|-------|
| running | 進行中 |
| blocked | 需要你 |
| done | 已完成 |
| idle | 閒置 |
| back | ← 返回 |
| menu | ☰ |

## Non-Goals

- This app does NOT manage or launch Claude Code sessions
- This app does NOT replace tmux
- This app does NOT provide task management features
- No configuration UI — all config comes from `mc-update.sh` calls
