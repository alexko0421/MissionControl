# Mission Control

A macOS floating dashboard that monitors multiple AI coding sessions in real time.

Supports **Claude Code** (Terminal / Conductor), **Antigravity**, **Codex**, and more.

## Features

- Real-time status tracking for all AI sessions (Running / Needs You / Done / Idle)
- Click the capsule bar or session detail to jump directly to the corresponding app
- Floats across all desktop spaces — always visible
- Orange border pulse + sound alert when a session needs your attention
- Focus Mode: lock onto a single session and silence other alerts

## Architecture

Mission Control is **not an agent** — it's a **command center**:

```
┌──────────────────────────────────────┐
│     Mission Control (Dashboard)       │
│  Reads ~/.mission-control/status.json │
└──────────┬───────────────────────────┘
           │ reads status
     ┌─────┼──────────┬────────────┐
     ▼     ▼          ▼            ▼
 Terminal  Conductor  Antigravity  Codex
 (Hooks)   (Hooks)   (Log scan)  (DB scan)
```

## File Structure

```
MissionControl/
├── MissionControlApp.swift   — App entry point
├── Models.swift              — Data models (Agent, AgentStatus, TerminalLine)
├── AgentStore.swift          — Data store: file watching, polling, external scanners
├── FloatingPanel.swift       — Floating window configuration
├── ContentView.swift         — UI: Capsule Bar, Session List, Summary, Settings
├── SharedComponents.swift    — Shared components (StatusDot, AlertPulse)
├── SettingsView.swift        — Settings panel
└── TMuxBridge.swift          — tmux CLI wrapper

scripts/
├── mc-claude-hook.py         — Claude Code Stop hook (AI summarization)
├── mc-prompt-hook.py         — Claude Code UserPromptSubmit hook
├── mc-pretool-hook.py        — Claude Code PreToolUse hook (detects approval wait)
├── mc-posttool-hook.py       — Claude Code PostToolUse hook
├── mc-antigravity-scanner.py — Antigravity log scanner
└── mc-codex-scanner.py       — Codex SQLite scanner
```

## Status Tracking

### Claude Code (Terminal / Conductor)

Configured via hooks in `~/.claude/settings.json`:

| Hook | Trigger | Sets Status |
|------|---------|-------------|
| `UserPromptSubmit` | User sends a message | → `running` |
| `PreToolUse` | Claude wants to use a tool (may need approval) | → `blocked` |
| `PostToolUse` | Tool execution complete | → `running` |
| `Stop` | Claude finishes responding | → AI summarizer decides |

### Antigravity

Scans `~/Library/Application Support/Antigravity/logs/` every 15 seconds to infer agent status.

### Codex

Reads `~/.codex/state_5.sqlite` threads table every 15 seconds to get session status.

## Status File

All statuses are aggregated into `~/.mission-control/status.json`. The app polls every 3 seconds, updating the UI only when data changes.

## Setup

1. Open `MissionControl.xcodeproj` in Xcode
2. Build & Run
3. Configure hooks in `~/.claude/settings.json` (see `scripts/` directory)
