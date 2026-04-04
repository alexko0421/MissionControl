# MissionControl → Vibe Island Parity Upgrade

**Date:** 2026-04-03
**Approach:** Gradual upgrade (方案 A) — upgrade each module incrementally while keeping the app usable throughout.
**Goal:** Feature parity with Vibe Island (https://vibeisland.app/). Open-source release.

---

## Section 1: Complete Hook Coverage + Env Var Collection

### Current State
4 hooks: `Stop`, `UserPromptSubmit`, `PermissionRequest`, `PostToolUse`

### Target
12 hook events matching Vibe Island:

| Hook Event | Purpose | Status |
|---|---|---|
| `SessionStart` | New session detected, create card | New |
| `SessionEnd` | Session ended, clean up card | New |
| `UserPromptSubmit` | User sent prompt, mark running | Existing |
| `PreToolUse` | Tool call in progress, show activity | New |
| `PostToolUse` | Tool call done, clear pending | Existing |
| `Notification` | Capture notification content inline | New |
| `Stop` | Agent stopped, summarize status | Existing |
| `SubagentStart` | Sub-agent started, nested display | New |
| `SubagentStop` | Sub-agent ended, clean up | New |
| `PreCompact` | Context compaction, show indicator | New |
| `PermissionRequest` | Permission request, block for approval | Existing |

### Env Var Collection
Every hook invocation collects process-context env vars via the bridge:

```
ITERM_SESSION_ID       → iTerm2 tab/session identification
TERM_SESSION_ID        → Terminal.app session identification
TERM_PROGRAM           → Terminal type (ghostty, xterm-ghostty, etc.)
TMUX / TMUX_PANE       → tmux session + pane identification
KITTY_WINDOW_ID        → Kitty terminal identification
__CFBundleIdentifier   → macOS app bundle ID
CMUX_WORKSPACE_ID      → cmux workspace
CMUX_SURFACE_ID        → cmux surface
CMUX_SOCKET_PATH       → cmux socket
```

Env vars are sent alongside hook data via socket, stored in the Agent model for terminal jumping.

### Agent Model Extension

```swift
struct Agent {
    // Existing fields...
    
    // New
    var terminalEnv: TerminalEnv?
    var subagentParentId: String?
    var isSubagent: Bool { subagentParentId != nil }
}

struct TerminalEnv: Codable {
    var itermSessionId: String?
    var termSessionId: String?
    var termProgram: String?
    var tmux: String?
    var tmuxPane: String?
    var kittyWindowId: String?
    var cfBundleIdentifier: String?
    var cmuxWorkspaceId: String?
    var cmuxSurfaceId: String?
    var cmuxSocketPath: String?
}
```

### Socket Message Extension
All hook messages include `terminal_env`:
```json
{
    "type": "status_update",
    "agent_id": "abc123",
    "event": "SessionStart",
    "cwd": "/Users/foo/project",
    "terminal_env": {
        "ITERM_SESSION_ID": "w0t0p0",
        "TERM_PROGRAM": "ghostty",
        "TMUX_PANE": "%3"
    }
}
```

### PermissionRequest Timeout
Increase from 300s to **86400s** (24 hours) to match Vibe Island.

---

## Section 2: Compiled Swift Bridge

### Current State
Python scripts (`mc-bridge.py`, `mc-claude-hook.py`, etc.) — several hundred ms startup overhead per hook invocation.

### Target
Single compiled Swift universal binary (arm64 + x86_64), ~400KB, replacing all Python scripts.

### CLI Interface

```
mc-bridge
├── --source claude|codex|gemini|cursor|copilot|...
├── --event SessionStart|Stop|PermissionRequest|...
├── --agent-id <id>
├── --cwd <path>
├── Automatic env var collection
├── Reads hook JSON data from stdin
└── Sends to ~/.mission-control/mc.sock
```

### Two Communication Modes

**Fire-and-forget** (most events):
```
Hook fires → bridge starts → read stdin → collect env vars → send to socket → exit(0)
```

**Wait-for-response** (PermissionRequest):
```
Hook fires → bridge starts → read stdin → send to socket → block waiting → receive allow/deny → exit(0/1)
```

### Installation Locations

```
MissionControl.app/Contents/Helpers/mc-bridge    # compiled binary
~/.mission-control/bin/mc-bridge                  # launcher shim (shell script)
```

Launcher shim resolution order:
1. Direct path: `/Applications/MissionControl.app/Contents/Helpers/mc-bridge`
2. Alternate: `~/Desktop/MissionControl.app/Contents/Helpers/mc-bridge`
3. Cache file: `~/.mission-control/.bridge-cache`
4. Spotlight: `mdfind kMDItemCFBundleIdentifier = "com.missioncontrol.app"`
5. Fallback: write to `~/.mission-control/status.json`

### Gemini Summarization
Existing logic from `mc-claude-hook.py` moves into the bridge:
- Read API key from `~/.mission-control/gemini-key.txt`
- On `Stop` event: call Gemini 2.0 Flash API
- Returns structured JSON: `{status, task, summary, nextAction}`
- No key → naive text extraction fallback

### Build Configuration
```yaml
# project.yml new target
mc-bridge:
  type: tool
  platform: macOS
  deploymentTarget: "14.0"
  settings:
    ARCHS: "arm64 x86_64"
  sources:
    - MissionControl/Bridge/
  postBuildScripts:
    - script: cp ${BUILT_PRODUCTS_DIR}/mc-bridge ${PROJECT_DIR}/MissionControl/Helpers/
```

### File Structure
```
MissionControl/Bridge/
├── main.swift              # entry point, arg parsing
├── SocketClient.swift      # connect to mc.sock, send/receive
├── EnvCollector.swift      # collect terminal env vars
├── HookRouter.swift        # dispatch by --event
├── GeminiSummarizer.swift  # Gemini API call
└── Models.swift            # shared message types
```

---

## Section 3: Terminal Jumping Strategies (13+ Terminals)

### Current State
Primarily tmux `select-window`/`select-pane` + AppleScript `AXRaise`. Insufficient for non-tmux environments or IDE integrated terminals.

### Target
Auto-select optimal jumping strategy based on `TerminalEnv` data.

### Strategy Matrix

| Terminal | Detection | Jumping Method |
|---|---|---|
| **iTerm2** | `ITERM_SESSION_ID` | AppleScript: iterate windows/tabs, match session ID, `set selected tab`, AXRaise |
| **iTerm2 + tmux -CC** | `ITERM_SESSION_ID` + tmux CC client | AppleScript: read `variable named "tmuxWindowPane"` |
| **Ghostty** | `TERM_PROGRAM=ghostty` | OSC2 title escape codes + tab UUID cache, write `/tmp/mc-osc2-title-<id>` |
| **Terminal.app** | `TERM_SESSION_ID` | AppleScript: match session ID, focus tab |
| **VS Code** | `__CFBundleIdentifier=com.microsoft.VSCode` | VSIX extension: URI handler `vscode://missioncontrol.terminal-focus/jump?pid=<pid>` |
| **Cursor** | `__CFBundleIdentifier=com.todesktop.runtime.cursor` | Same as VS Code with `cursor://` URI scheme |
| **Windsurf** | `__CFBundleIdentifier` match | Same as VS Code strategy |
| **Kitty** | `KITTY_WINDOW_ID` | `kitty @ focus-window --match id:<id>` remote control API |
| **Warp** | `TERM_PROGRAM=WarpTerminal` | AppleScript + tab name matching |
| **tmux (standalone)** | `TMUX` + `TMUX_PANE` | `tmux select-window -t` + `select-pane -t` + AXRaise host terminal |
| **cmux** | `CMUX_SOCKET_PATH` | JSON-RPC via socket: `{"method": "focus", "params": {"surface": "<id>"}}` |
| **Alacritty** | `__CFBundleIdentifier` match | AXRaise only (no tab API) |
| **Hyper** | `__CFBundleIdentifier` match | AXRaise only |

### Jump Engine Architecture

```swift
protocol TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool
    static func jump(env: TerminalEnv) async throws
}

struct JumpEngine {
    static let jumpers: [TerminalJumper.Type] = [
        ITermJumper.self,
        GhosttyJumper.self,
        TerminalAppJumper.self,
        VSCodeJumper.self,
        CursorJumper.self,
        KittyJumper.self,
        WarpJumper.self,
        CmuxJumper.self,
        TmuxJumper.self,
        GenericJumper.self,
    ]
    
    static func jump(to agent: Agent) async throws {
        guard let env = agent.terminalEnv else {
            try await GenericJumper.jump(env: .init())
            return
        }
        for jumper in jumpers {
            if jumper.canHandle(env: env) {
                try await jumper.jump(env: env)
                return
            }
        }
    }
}
```

### VSIX Extension (VS Code / Cursor / Windsurf)

```
MissionControl/VSIXExtension/
├── package.json          # activation: onUri
├── extension.ts          # URI handler, match terminal by PID
└── build.sh              # package as .vsix
```

Extension logic:
1. Register URI handler `missioncontrol.terminal-focus`
2. On jump request → iterate `vscode.window.terminals`
3. Match by `terminal.processId`
4. `terminal.show(false)` — focus without stealing keyboard

Auto-install on app first launch:
```bash
code --install-extension mc-terminal-focus.vsix
cursor --install-extension mc-terminal-focus.vsix
```

### Ghostty OSC2 Strategy

Bridge writes title marker on `SessionStart`:
```swift
print("\u{1b}]2;MC:\(agentId)\u{07}", terminator: "")
```

App maintains `GhosttyTabCache` with tab UUIDs for rename-proof matching.

### File Structure
```
MissionControl/MissionControl/Jumping/
├── JumpEngine.swift
├── TerminalJumper.swift      # protocol
├── ITermJumper.swift
├── GhosttyJumper.swift
├── TerminalAppJumper.swift
├── VSCodeJumper.swift        # shared for VS Code/Cursor/Windsurf
├── KittyJumper.swift
├── WarpJumper.swift
├── CmuxJumper.swift
├── TmuxJumper.swift
└── GenericJumper.swift       # AXRaise fallback
```

---

## Section 4: Notch UI

### Current State
`FloatingPanel` (NSPanel) fixed at top-center of screen, 360px wide.

### Target
Notch Macs → embed in notch area; non-notch / external display → compact floating bar.

### Notch Detection

```swift
struct NotchDetector {
    static func hasNotch(screen: NSScreen) -> Bool {
        guard let _ = screen.auxiliaryTopLeftArea,
              let _ = screen.auxiliaryTopRightArea else {
            return false
        }
        return true
    }
    
    static func notchRect(screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let safeArea = screen.safeAreaInsets
        let notchWidth: CGFloat = 200
        let menuBarHeight = safeArea.top
        return NSRect(
            x: frame.midX - notchWidth / 2,
            y: frame.maxY - menuBarHeight,
            width: notchWidth,
            height: menuBarHeight
        )
    }
}
```

### NotchPanel

```swift
class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    func configure() {
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        styleMask = [.borderless, .nonactivatingPanel]
    }
}
```

Key: `canBecomeKey = false` + `nonactivatingPanel` → never steals focus.

### Three UI States

**1. Collapsed (default)**
- Notch Mac: hidden behind notch, only status dots visible on sides
- Non-notch: compact capsule bar at top center (similar to current)

**2. Hover / Peek**
- Mouse enters notch area → smooth expansion showing priority agent status
- Width expands to ~360px

**3. Expanded (click)**
- Full session list, approval cards, settings
- Expands downward from notch anchor
- Same functionality as current SessionListPanel

### Animation

```swift
struct NotchShape: Shape {
    var expansion: CGFloat  // 0 = collapsed, 1 = fully expanded
    
    func path(in rect: CGRect) -> Path {
        let cornerRadius = 12 * (1 - expansion) + 20 * expansion
        let width = notchWidth + (expandedWidth - notchWidth) * expansion
        let height = notchHeight + (expandedHeight - notchHeight) * expansion
        // ...rounded rect path
    }
}
```

Spring animation: `.spring(response: 0.3, dampingFraction: 0.8)`

### Screen Switching

Monitor `NSApplication.didChangeScreenParametersNotification`:
- Window dragged to external display → auto-switch to floating bar mode
- Back to MacBook screen → auto-switch to notch mode

### File Structure (includes ContentView.swift decomposition)
```
MissionControl/MissionControl/UI/
├── NotchPanel.swift          # NSPanel subclass
├── NotchDetector.swift       # notch detection + positioning
├── NotchContentView.swift    # SwiftUI root for notch
├── NotchShape.swift          # custom notch shape + animation
├── CapsuleBar.swift          # extracted from ContentView
├── SessionListPanel.swift    # extracted from ContentView
├── SummaryPanel.swift        # extracted from ContentView
└── AgentAlertPanel.swift     # extracted from ContentView
```

This section also decomposes the current 3600+ line `ContentView.swift` into focused view files.

---

## Section 5: StatusLine Rate Limit Tracking

### Current State
No rate limit display.

### Target
Real-time Claude API usage display (5-hour / 7-day windows) in the notch UI.

### Hook Installation

Add to `~/.claude/settings.json`:
```json
{
    "statusLine": "~/.mission-control/bin/mc-statusline"
}
```

### mc-statusline Script

```bash
#!/bin/bash
INPUT=$(cat)
echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
rl = data.get('rate_limits', {})
if rl:
    json.dump(rl, open('/tmp/mc-rate-limits.json', 'w'))
" 2>/dev/null
```

Later replaced by compiled Swift binary.

### App-Side Monitoring

```swift
struct RateLimitMonitor {
    let path = "/tmp/mc-rate-limits.json"
    
    // Field names TBD — must match actual Claude Code statusLine JSON output.
    // Inspect real output by running: echo '{}' | claude --status-line-command cat
    // Then update these fields to match.
    struct RateLimits: Codable {
        var requestsRemaining5h: Int?
        var requestsLimit5h: Int?
        var requestsRemaining7d: Int?
        var requestsLimit7d: Int?
    }
    
    // DispatchSource.makeFileSystemObjectSource monitors file changes
    // Read + update UI on every change
}
```

### UI Display

In notch expanded state, bottom bar shows:
```
⚡ 42/50 (5h)  ·  280/500 (7d)
```

Color coding:
- Green: >50% remaining
- Yellow: 20-50%
- Red: <20%
- Near-depletion: notch flashes orange

---

## Section 6: Auto Hook Recovery + Sound Effects

### 6A: Auto Hook Recovery

#### Problem
Other tools (e.g., Claude Code updates) can overwrite `~/.claude/settings.json`, removing MissionControl hooks.

#### Solution

```swift
struct HookGuard {
    let watchPaths = [
        "~/.claude/settings.json",
        "~/.codex/config.toml",
        "~/.gemini/settings.json"
    ]
    
    // DispatchSource.makeFileSystemObjectSource (kqueue) monitoring
    // On file change: check if MC hooks were removed
    // If removed → merge back, preserving JSONC comments
}
```

Flow:
1. App startup: record current hook config as baseline
2. `DispatchSource` monitors file changes (kqueue, zero CPU)
3. File change → read new content → diff check MissionControl hook entries
4. If hooks removed → merge back (preserve other tools' config)
5. Support JSONC (JSON with comments)

### 6B: Sound Effects

#### Current State
System `"Ping"` sound only.

#### Target
8-bit chiptune synthesis, real-time generated, no audio files needed.

```swift
import AVFoundation

class ChiptuneEngine {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    enum Waveform { case square, triangle, sine, noise }
    
    func playAlert() {
        // Rising: C5 → E5 → G5, 80ms each, square wave
        let notes: [(freq: Float, duration: Float)] = [
            (523.25, 0.08), (659.25, 0.08), (783.99, 0.12)
        ]
        synthesize(notes: notes, waveform: .square)
    }
    
    func playApproved() {
        // Short confirm: G5 → C6
        synthesize(notes: [(783.99, 0.06), (1046.5, 0.1)], waveform: .triangle)
    }
    
    func playDenied() {
        // Falling: E5 → C4
        synthesize(notes: [(659.25, 0.08), (261.63, 0.12)], waveform: .square)
    }
    
    func playSessionDone() {
        // Complete: C5 → E5 → G5 → C6
        synthesize(notes: [
            (523.25, 0.06), (659.25, 0.06),
            (783.99, 0.06), (1046.5, 0.15)
        ], waveform: .triangle)
    }
}
```

Sound triggers:

| Event | Sound |
|---|---|
| Agent needs approval | `playAlert()` |
| User allows | `playApproved()` |
| User denies | `playDenied()` |
| Agent done | `playSessionDone()` |
| New session | Silent |

Audio device switching handled via `AVAudioEngineConfigurationChange` notification.

### File Structure
```
MissionControl/MissionControl/
├── HookGuard.swift
├── Audio/
│   └── ChiptuneEngine.swift
```

---

## Implementation Order

1. Hook coverage + env var collection (Section 1)
2. Compiled Swift bridge (Section 2)
3. Terminal jumping strategies (Section 3)
4. Notch UI (Section 4)
5. StatusLine rate limit (Section 5)
6. Auto hook recovery + sound effects (Section 6)

Each step is independently deployable and immediately adds value.
