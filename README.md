# Mission Control

macOS SwiftUI app for managing parallel Claude Code / Conductor sessions.

## Setup

1. Create new Xcode project: File → New → Project → macOS → App
2. Set Product Name: `MissionControl`
3. Replace all generated Swift files with the files in `/MissionControl/` folder
4. Add `com.apple.security.temporary-exception.sbpl` entitlement if needed for shell execution

## File Structure

```
MissionControl/
├── MissionControlApp.swift   — App entry point
├── Models.swift              — Agent, TerminalLine, AgentStatus
├── AgentStore.swift          — Data store, file watching, tmux polling
├── TMuxBridge.swift          — tmux CLI wrapper
├── ContentView.swift         — Navigation (list ↔ detail)
├── AgentListView.swift       — List screen + stats bar
└── AgentDetailView.swift     — Detail screen + sidebar + input
```

## How agents report status

Each Claude Code session calls `mc-update.sh` when it completes a task or needs input:

```bash
# From inside a Claude Code session:
~/.mission-control/mc-update.sh \
  "asami-voice" \       # agent id
  "blocked" \           # running | blocked | done | idle
  "等待你決定動畫方向" \  # current task (short)
  "已完成卡片動畫，..." \ # summary
  "選擇 A 或 B" \       # next action needed
  "conductor" 0 0        # tmux session, window, pane
```

Status file lives at: `~/.mission-control/status.json`
App auto-reloads when file changes.

## tmux Integration

App reads live terminal output via:
```bash
tmux capture-pane -t "session:window.pane" -p -S -30
```

And sends commands via:
```bash
tmux send-keys -t "session:window.pane" "your command" Enter
```
