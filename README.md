# Mission Control

<p align="center">
  <img src="PerfectGeometric_M.png" width="128" alt="Mission Control" />
</p>

<p align="center">
  A macOS floating dashboard that monitors multiple AI coding sessions in real time.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#features">Features</a> •
  <a href="#supported-apps">Supported Apps</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#build-from-source">Build from Source</a>
</p>

---

## Quick Start

**1. Install hooks for Claude Code:**

```bash
npx mission-control-ai setup
```

**2. Download the app** from [Releases](https://github.com/alexko0421/MissionControl/releases) and run it.

That's it. Your AI coding sessions will appear in Mission Control automatically.

## Features

- **Real-time status tracking** — Running / Needs You / Done / Idle
- **Click to jump** — click any session to switch to its app and window
- **Floats across all Spaces** — always visible, never in the way
- **Alert pulse** — orange border + sound when a session needs your attention
- **Focus Mode** — lock onto one session, silence other alerts
- **Multi-language** — English and Chinese

## Supported Apps

| App | Detection |
|-----|-----------|
| **Claude Code** (Terminal / Conductor) | Hooks (automatic via `npx mission-control-ai setup`) |
| **Antigravity** | Log scanning (`~/Library/Application Support/Antigravity/logs/`) |
| **Codex** | SQLite scanning (`~/.codex/state_5.sqlite`) |

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

## CLI Commands

```bash
npx mission-control-ai setup       # Install hooks for Claude Code
npx mission-control-ai uninstall   # Remove hooks
npx mission-control-ai status      # Show current session status
```

### What `setup` does

1. Copies hook scripts to `~/.mission-control/hooks/`
2. Configures `~/.claude/settings.json` with four hooks:

| Hook | Trigger | Sets Status |
|------|---------|-------------|
| `UserPromptSubmit` | User sends a message | → `running` |
| `PreToolUse` | Claude wants to use a tool (may need approval) | → `blocked` |
| `PostToolUse` | Tool execution complete | → `running` |
| `Stop` | Claude finishes responding | → AI-summarized status |

## Build from Source

```bash
git clone https://github.com/alexko0421/MissionControl.git
cd MissionControl
open MissionControl.xcodeproj
```

Build & Run in Xcode (requires macOS 14.0+).

## Status File

All statuses are aggregated into `~/.mission-control/status.json`. The app polls every 3 seconds, updating the UI only when data changes.

## License

[MIT](LICENSE) — Ko Chunlong
