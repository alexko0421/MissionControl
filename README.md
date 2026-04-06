# Mission Control

<p align="center">
  <img src="PerfectGeometric_M.png" width="128" alt="Mission Control" />
</p>

<p align="center">
  A macOS floating dashboard that monitors and controls multiple AI coding sessions in real time.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#features">Features</a> &bull;
  <a href="#how-it-works">How It Works</a> &bull;
  <a href="#supported-agents">Supported Agents</a> &bull;
  <a href="#build-from-source">Build from Source</a>
</p>

---

## Quick Start

**1. Install hooks for Claude Code:**

```bash
npx mission-control-ai setup
```

**2. Download the app** from [Releases](https://github.com/alexko0421/MissionControl/releases) and run it.

**3. Start coding.** Your AI sessions will appear in Mission Control automatically.

For remote approval (approve tool use from the dashboard), run Claude inside tmux:

```bash
tmux new -s work
claude
```

## Features

- **Real-time status tracking** &mdash; Running / Done / Idle, driven by `stop_reason` (no keyword guessing)
- **Remote approval** &mdash; approve or deny Bash/Write/Edit tool use from the dashboard (tmux + AppleScript fallback)
- **Click to jump** &mdash; click any session to switch to its terminal window and pane
- **Floats across all Spaces** &mdash; always visible, never steals focus
- **Alert pulse** &mdash; sound + visual alert when a session needs attention
- **Focus Mode** &mdash; lock onto one session, silence other alerts
- **Multi-language** &mdash; English and Chinese (Simplified & Traditional)
- **Permission card** &mdash; shows tool name, command, file path, and unified diff preview for Edit tools

## How It Works

Mission Control uses a **hook-based architecture** with a Unix domain socket for real-time bidirectional communication:

```
Claude Code Session
    |
    |-- UserPromptSubmit hook --> status: running
    |-- PreToolUse hook -------> permission card (Bash/Write/Edit)
    |-- Stop hook -------------> status: done (end_turn) or running (tool_use)
    |
    v
mc-bridge-swift (compiled binary)
    |
    v  Unix domain socket (~/.mission-control/mc.sock)
    |
MissionControl.app (SwiftUI)
    |
    |-- Shows status, approval cards, alerts
    |-- User clicks Allow --> worker sends tmux send-keys / AppleScript
    |-- Terminal auto-confirms
```

### Approval Flow

When Claude needs permission to run a tool:

1. **PreToolUse hook** launches a background worker
2. Worker sends `permission_request` to MissionControl via socket
3. MissionControl shows an approval card with tool details
4. User clicks **Allow** or **Deny**
5. Worker receives the decision and sends keystrokes to the terminal:
   - **tmux**: `tmux send-keys -t <pane> Enter` (preferred)
   - **AppleScript**: `key code 36` fallback for non-tmux terminals

Safe tools (Read, Grep, Glob, etc.) are auto-approved silently.

### Status Detection

Status is determined purely by Claude Code's `stop_reason`:

| stop_reason | Status | Badge |
|-------------|--------|-------|
| `end_turn` | Done | Blue |
| `tool_use` | Running | Green |
| other | Running | Green |

No keyword matching, no AI summarization, no guessing.

## Supported Agents

| Agent | Integration |
|-------|-------------|
| **Claude Code** | Full support (hooks + approval) |
| **Codex CLI** | Status monitoring via hooks |
| **Gemini CLI** | Status monitoring via hooks |
| **Cursor** | Status monitoring via hooks |

## Project Structure

```
MissionControl/
  MissionControl/          # SwiftUI app
    MissionControlApp.swift
    AgentStore.swift        # Central state management
    MCSocketServer.swift    # Unix socket server
    ContentView.swift       # Main UI
    PermissionCardView.swift
    Models.swift
  Bridge/                   # Compiled hook binary (mc-bridge-swift)
    main.swift
    HookRouter.swift        # Routes hook events
    SocketClient.swift      # Socket client
    BridgeModels.swift
    EnvCollector.swift      # Detects tmux, app, tty
```

## Build from Source

```bash
git clone https://github.com/alexko0421/MissionControl.git
cd MissionControl
open MissionControl.xcodeproj
```

Build & Run in Xcode (requires macOS 14.0+, Swift 5.9+).

To rebuild the bridge binary:

```bash
swiftc -O -o ~/.mission-control/bin/mc-bridge-swift \
  Bridge/main.swift Bridge/HookRouter.swift Bridge/SocketClient.swift \
  Bridge/BridgeModels.swift Bridge/EnvCollector.swift
```

## Security

- **Fail-closed permissions** &mdash; transport errors result in no decision (Claude shows native prompt)
- **No credentials stored** &mdash; no API keys, no cloud services, all data stays local
- **Trusted binary paths only** &mdash; bridge launcher only executes from `~/.mission-control/bin` or `/Applications`
- **Socket-only communication** &mdash; Unix domain socket, no network exposure

## License

[MIT](LICENSE) &mdash; Ko Chunlong
