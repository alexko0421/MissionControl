# MissionControl v2 — 升级设计文档

## 概述

将 MissionControl 从 file-based 单向轮询架构升级为 Unix socket 双向通讯架构，新增 Permission Management、Plan Review、多 Agent 支持。

## 目标

1. **Unix Socket 双向通讯** — 取代 status.json file polling，实现即时状态更新同 approve/deny 交互
2. **Permission Management** — 喺 GUI 直接 approve/deny agent 嘅 tool calls，以 inline 卡片形式嵌入 session list
3. **Plan Review** — 预览 AI 生成嘅 plan（Markdown rendering），approve/reject
4. **多 Agent 支持** — 统一 hook 自动注入，支持 Claude Code、Codex、Gemini CLI、Cursor Agent
5. **保持现有 UI** — capsule bar + floating panel 设计唔变，音效唔变

## 架构

### 系统架构

```
┌──────────────────────────────────────┐
│     MissionControl.app (SwiftUI)     │
│                                      │
│  ┌──────────────┐  ┌──────────────┐  │
│  │  AgentStore   │  │  UI Views    │  │
│  │  (updated)    │←→│  (updated)   │  │
│  └──────┬───────┘  └──────────────┘  │
│         │                            │
│  ┌──────┴───────┐                    │
│  │ MCSocketServer│                   │
│  │ (new)         │                   │
│  └──────┬───────┘                    │
└─────────┼────────────────────────────┘
          │ ~/.mission-control/mc.sock
          │
    ┌─────┼──────────────────────────┐
    │     │    mc-bridge (new)       │
    │     │    轻量 socket client    │
    │     └─────────────────────────│
    │                               │
    ├── Claude Code hooks ──────────┤
    ├── Codex hooks ────────────────┤
    ├── Gemini CLI hooks ───────────┤
    └── Cursor hooks ───────────────┘
```

### 核心组件

#### 1. MCSocketServer（新增 · Swift）

App 内嵌嘅 Unix domain socket server，监听 `~/.mission-control/mc.sock`。

职责：
- 接受 agent hook 嘅连接
- 解析 JSON messages（status update、permission request、plan review）
- 将状态变更推送到 AgentStore
- 将用户嘅 approve/deny 决定送返对应嘅 agent 连接

生命周期：
- App 启动时 `startListening()`，创建 socket 文件并监听
- 每个 agent 连接维持一个 `MCClientConnection`，track request/response
- App 退出时 cleanup socket 文件

#### 2. mc-bridge（新增 · 轻量 binary）

取代现有嘅直接写 status.json 嘅 Python hooks。所有 hook 调用 mc-bridge 嚟同 app 通讯。

实现语言选择：Python script（保持同现有 hooks 一致，降低部署复杂度）。

用法：
```bash
# 状态更新
mc-bridge status --agent-id abc123 --status running --task "重构 API"

# Permission request（阻塞直到收到 approve/deny）
mc-bridge permission --agent-id abc123 --tool Bash --command "rm -rf dist/"
# 输出: {"decision": "approve"} 或 {"decision": "deny"}

# Plan review（阻塞直到收到 approve/deny）  
mc-bridge plan --agent-id abc123 --markdown "## Plan\n1. ..."
# 输出: {"decision": "approve"} 或 {"decision": "deny"}
```

工作流程：
1. 连接 `~/.mission-control/mc.sock`
2. 发送 JSON message
3. 对于 permission/plan request，阻塞等待 response
4. 输出 response 到 stdout，退出

Fallback：如果 socket 唔存在（app 未运行），fallback 到写 status.json（向后兼容）。

#### 3. CLI setup 命令（升级）

扩展 `npx mission-control-ai setup` 支持多个 agent：

```bash
npx mission-control-ai setup              # 自动检测所有已安装 agent
npx mission-control-ai setup claude-code   # 只设置 Claude Code
npx mission-control-ai setup codex         # 只设置 Codex
```

自动检测逻辑：
- **Claude Code**: 检查 `~/.claude/settings.json` 存在
- **Codex**: 检查 `~/.codex/config.toml` 存在
- **Gemini CLI**: 检查 `~/.gemini/settings.json` 存在
- **Cursor**: 检查 `~/.cursor/hooks.json` 存在

每个 agent 嘅 setup：
1. 将 mc-bridge 部署到 `~/.mission-control/bin/`
2. 将对应 hook scripts 部署到 `~/.mission-control/hooks/`
3. 修改 agent 嘅 config file 注入 hook entries

## 通讯协议

所有 message 以 newline-delimited JSON 格式喺 Unix socket 上传输。每条 message 以 `\n` 结尾。

### Agent → App（上行 messages）

#### status_update
```json
{
  "type": "status_update",
  "agent_id": "abc123",
  "agent_type": "claude-code",
  "name": "kochunlong",
  "status": "running",
  "task": "重构 API endpoint",
  "summary": "已完成 3/5 个 endpoint",
  "next_action": "继续处理 /users endpoint",
  "worktree": "/Users/kochunlong/project",
  "app": "Terminal",
  "tmux_session": "main",
  "tmux_window": 0,
  "tmux_pane": 0
}
```

#### permission_request
```json
{
  "type": "permission_request",
  "request_id": "req_abc123",
  "agent_id": "abc123",
  "tool": "Bash",
  "tool_input": {
    "command": "rm -rf dist/ && npm run build",
    "description": "Clean and rebuild"
  }
}
```

#### plan_review
```json
{
  "type": "plan_review",
  "request_id": "req_def456",
  "agent_id": "abc123",
  "markdown": "## Implementation Plan\n\n1. Refactor AgentStore...\n2. Add socket server..."
}
```

### App → Agent（下行 messages）

#### permission_response
```json
{
  "type": "permission_response",
  "request_id": "req_abc123",
  "decision": "approve"
}
```

#### plan_response
```json
{
  "type": "plan_response",
  "request_id": "req_def456",
  "decision": "approve"
}
```

`decision` 值：`"approve"` 或 `"deny"`

## UI 变更

### AgentStore 变更

移除：
- `statusFile` / `lastFileData` / file watcher 相关代码
- `loadFromFile()` / `saveToFile()` 基于 file polling 嘅逻辑
- 3 秒 polling timer（socket 係 event-driven，唔需要 poll）

新增：
- `socketServer: MCSocketServer` — 管理 socket 连接
- `pendingPermissions: [PermissionRequest]` — 待处理嘅 permission requests
- `pendingPlans: [PlanReview]` — 待处理嘅 plan reviews
- `approvePermission(requestId:)` / `denyPermission(requestId:)`
- `approvePlan(requestId:)` / `denyPlan(requestId:)`

保留：
- `pollTerminals()` — tmux 轮询仍然需要（tmux 冇 push 机制）
- `runExternalScanners()` — 外部 scanner 保留
- `cleanupStaleAgents()` — stale cleanup 保留
- Alert 机制（`activeAlert`、sound）保留
- Focus Mode 保留
- ViewState enum 保留，新增 `.permission(requestId:)` case

### Session List UI 变更

喺 session row 入面，当该 agent 有 pending permission 或 plan review 时，展开显示 inline 卡片：

**Permission 卡片：**
- 显示 tool 名称 + tool input（command / file path）
- Approve（绿色）+ Deny（红色）按钮
- 点击后卡片消失，状态更新为 running（approve）或保持 blocked（deny）

**Plan Review 卡片：**
- Markdown 内容用 SwiftUI `Text` 或者轻量 Markdown renderer 显示
- Approve + Reject 按钮
- 可滚动，限制最大高度

### Agent Model 变更

`Agent` struct 新增：
```swift
var agentType: String?  // "claude-code", "codex", "gemini-cli", "cursor"
var pendingPermission: PermissionRequest?
var pendingPlan: PlanReview?
```

新增 models：
```swift
struct PermissionRequest: Identifiable, Codable {
    var id: String  // request_id
    var tool: String
    var toolInput: [String: String]
    var receivedAt: Date
}

struct PlanReview: Identifiable, Codable {
    var id: String  // request_id
    var markdown: String
    var receivedAt: Date
}
```

### Agent 图标扩展

`appIcon` 属性扩展支持新 agent types：
- codex → `curlybraces`
- gemini-cli → `sparkles`（或自定义）
- cursor → `cursorarrow.and.square.on.square.dashed`

## Hook 变更

### Claude Code Hooks

现有 4 个 Python hooks 全部改为调用 mc-bridge：

| Hook | 现有行为 | 新行为 |
|------|---------|--------|
| `UserPromptSubmit` | 写 status.json (running) | `mc-bridge status --status running` |
| `PreToolUse` | 写 status.json (blocked) | `mc-bridge permission --tool X --command Y`（阻塞等待 response） |
| `PostToolUse` | 写 status.json (running) | `mc-bridge status --status running` |
| `Stop` | 写 status.json (AI summary) | `mc-bridge status --status done --summary "..."` |

**关键变更：PreToolUse hook 变成阻塞式。** 当 Claude Code 发出 PreToolUse hook 时，mc-bridge 连接 socket，发送 permission_request，然后阻塞等待 app 回传 approve/deny。如果 approve，hook 正常返回（Claude Code 继续执行）。如果 deny，hook 输出 `{"decision": "deny"}` 令 Claude Code 跳过该 tool。

Timeout：如果 10 秒内冇收到 response，自动 approve（避免 app 未运行时阻塞 agent）。

**Deny 行为：** Claude Code 嘅 PreToolUse hook 支持 `{"decision": "block", "reason": "User denied in MissionControl"}` 输出格式嚟阻止 tool 执行。mc-bridge 喺收到 deny response 后输出呢个 JSON 到 stdout。

### 其他 Agent Hooks

每个 agent 需要对应嘅 hook script，调用同一个 mc-bridge：

- **Codex**: hook 写入 `~/.codex/hooks.json`
- **Gemini CLI**: hook 写入 `~/.gemini/settings.json`
- **Cursor**: hook 写入 `~/.cursor/hooks.json`

Hook 内容大致相同，只系 agent_type 同 config 路径唔同。

## 向后兼容

- mc-bridge 有 file fallback：socket 唔存在时写 status.json
- App 启动时如果有旧嘅 status.json，做一次性 migration 加载现有 sessions
- CLI `uninstall` 命令需要更新，清理新嘅 hook entries

## 文件变更清单

### 新增文件
- `MissionControl/MCSocketServer.swift` — Unix socket server
- `MissionControl/MCClientConnection.swift` — 单个 client 连接管理
- `MissionControl/SocketMessage.swift` — message types + encoding/decoding
- `MissionControl/PermissionCardView.swift` — permission inline 卡片 UI
- `MissionControl/PlanReviewView.swift` — plan review inline 卡片 UI
- `cli/hooks/mc-bridge.py` — socket client bridge
- `cli/hooks/mc-codex-hook.py` — Codex hook
- `cli/hooks/mc-gemini-hook.py` — Gemini CLI hook
- `cli/hooks/mc-cursor-hook.py` — Cursor hook

### 修改文件
- `MissionControl/AgentStore.swift` — 移除 file polling，加入 socket server 集成
- `MissionControl/Models.swift` — 新增 PermissionRequest、PlanReview models，Agent 加字段
- `MissionControl/ContentView.swift` — session list 加入 permission/plan 卡片
- `MissionControl/MissionControlApp.swift` — app 启动/退出时管理 socket lifecycle
- `cli/bin/cli.mjs` — setup 命令支持多 agent
- `cli/hooks/mc-claude-hook.py` — 改用 mc-bridge（Stop hook 保留 AI summary 逻辑）
- `cli/hooks/mc-pretool-hook.py` — 改为调用 mc-bridge permission（阻塞式）
- `cli/hooks/mc-posttool-hook.py` — 改为调用 mc-bridge status
- `cli/hooks/mc-prompt-hook.py` — 改为调用 mc-bridge status

### 删除文件
无（保留所有现有文件，渐进修改）
