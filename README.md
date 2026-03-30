# Mission Control

macOS 浮动监控面板，实时追踪多个 AI coding session 的状态。

支持 **Claude Code**（Terminal / Conductor）、**Antigravity**、**Codex** 等 app。

## 功能

- 实时显示所有 AI session 的状态（进行中 / 需要你 / 已完成 / 闲置）
- 点击 capsule bar 或 session 详情直接跳转到对应 app
- 浮动在所有桌面空间，随时可见
- 当 session 需要你操作时，橙色边框闪烁提醒 + 声音提示
- 支持 Focus Mode：锁定关注单个 session

## 架构

Mission Control 本身**不是 agent**，而是一个**指挥台**：

```
┌─────────────────────────────────┐
│     Mission Control (监控面板)     │
│  读取 ~/.mission-control/status.json │
└──────────┬──────────────────────┘
           │ 读取状态
     ┌─────┼─────────┬────────────┐
     ▼     ▼         ▼            ▼
 Terminal  Conductor  Antigravity  Codex
 (Hooks)   (Hooks)   (Log扫描)   (DB扫描)
```

## 文件结构

```
MissionControl/
├── MissionControlApp.swift   — App 入口
├── Models.swift              — 数据模型（Agent, AgentStatus, TerminalLine）
├── AgentStore.swift          — 数据中心：文件监听、轮询、外部扫描器
├── FloatingPanel.swift       — 浮动窗口配置
├── ContentView.swift         — UI：Capsule Bar、Session List、Summary、Settings
├── SharedComponents.swift    — 共用组件（StatusDot、AlertPulse）
├── SettingsView.swift        — 设置页
└── TMuxBridge.swift          — tmux CLI 封装

scripts/
├── mc-claude-hook.py         — Claude Code Stop hook（Gemini 摘要）
├── mc-prompt-hook.py         — Claude Code UserPromptSubmit hook
├── mc-pretool-hook.py        — Claude Code PreToolUse hook（检测等待审批）
├── mc-posttool-hook.py       — Claude Code PostToolUse hook
├── mc-antigravity-scanner.py — Antigravity log 扫描器
└── mc-codex-scanner.py       — Codex SQLite 扫描器
```

## 状态追踪机制

### Claude Code（Terminal / Conductor）

通过 `~/.claude/settings.json` 配置 hooks：

| Hook | 触发时机 | 设置状态 |
|------|---------|---------|
| `UserPromptSubmit` | 用户发送消息 | → `running` |
| `PreToolUse` | Claude 要用工具（可能等待审批）| → `blocked` |
| `PostToolUse` | 工具执行完毕 | → `running` |
| `Stop` | Claude 回复完成 | → Gemini 判断 |

### Antigravity

每 15 秒扫描 `~/Library/Application Support/Antigravity/logs/` 的 agent log，推断状态。

### Codex

每 15 秒读取 `~/.codex/state_5.sqlite` 的 threads 表，获取 session 状态。

## 状态文件

所有状态汇总到 `~/.mission-control/status.json`，App 每 3 秒轮询读取（仅在数据变化时更新 UI）。

## Setup

1. 用 Xcode 打开 `MissionControl.xcodeproj`
2. Build & Run
3. 确保 `~/.claude/settings.json` 中配置了 hooks（参考 `scripts/` 目录）
