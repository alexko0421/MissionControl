# Vibe Island Parity Upgrade — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade MissionControl to feature parity with Vibe Island — complete hook coverage, compiled Swift bridge, 13+ terminal jumping strategies, notch UI, rate limit tracking, auto hook recovery, and chiptune sound effects.

**Architecture:** Gradual upgrade of existing codebase. Each task is independently deployable. Communication layer stays on Unix Domain Socket (`~/.mission-control/mc.sock`). Python hooks replaced by compiled Swift bridge binary. UI migrated from floating panel to notch-aware panel with ContentView decomposition.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+, AVFoundation (audio synthesis), TypeScript (VSIX extension), XcodeGen

---

## Task 1: Extend Socket Message Protocol + Agent Model

**Files:**
- Modify: `MissionControl/MissionControl/SocketMessage.swift`
- Modify: `MissionControl/MissionControl/Models.swift`

- [ ] **Step 1: Add `TerminalEnv` struct to Models.swift**

Add after the `AgentQuestion` struct (after line 112):

```swift
// MARK: - Terminal Environment (for precise terminal jumping)

struct TerminalEnv: Codable, Equatable {
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

    enum CodingKeys: String, CodingKey {
        case itermSessionId = "ITERM_SESSION_ID"
        case termSessionId = "TERM_SESSION_ID"
        case termProgram = "TERM_PROGRAM"
        case tmux = "TMUX"
        case tmuxPane = "TMUX_PANE"
        case kittyWindowId = "KITTY_WINDOW_ID"
        case cfBundleIdentifier = "__CFBundleIdentifier"
        case cmuxWorkspaceId = "CMUX_WORKSPACE_ID"
        case cmuxSurfaceId = "CMUX_SURFACE_ID"
        case cmuxSocketPath = "CMUX_SOCKET_PATH"
    }
}
```

- [ ] **Step 2: Add new fields to Agent struct**

In the `Agent` struct, add after `var agentType: String?` (line 130):

```swift
    var terminalEnv: TerminalEnv?
    var subagentParentId: String?
    var isSubagent: Bool { subagentParentId != nil }
    var tty: String?
```

Update `CodingKeys` to include new fields:

```swift
    enum CodingKeys: String, CodingKey {
        case id, name, status, task, summary, terminalLines, nextAction, updatedAt
        case worktree, app, tmuxSession, tmuxWindow, tmuxPane, agentType
        case terminalEnv, subagentParentId, tty
    }
```

- [ ] **Step 3: Add `terminal_env`, `event`, `subagent_parent_id`, `tty` to IncomingMessage**

In `SocketMessage.swift`, add fields to `IncomingMessage`:

```swift
struct IncomingMessage: Codable {
    let type: IncomingMessageType

    var agentId: String?
    var agentType: String?
    var name: String?
    var status: String?
    var task: String?
    var summary: String?
    var nextAction: String?
    var worktree: String?
    var app: String?
    var tmuxSession: String?
    var tmuxWindow: Int?
    var tmuxPane: Int?

    var requestId: String?
    var tool: String?
    var toolInput: [String: String]?

    var markdown: String?

    // question fields
    var question: String?
    var options: [[String: String]]?

    // New fields for Vibe Island parity
    var event: String?
    var terminalEnv: TerminalEnv?
    var subagentParentId: String?
    var tty: String?
    var cwd: String?

    enum CodingKeys: String, CodingKey {
        case type
        case agentId = "agent_id"
        case agentType = "agent_type"
        case name, status, task, summary
        case nextAction = "next_action"
        case worktree, app
        case tmuxSession = "tmux_session"
        case tmuxWindow = "tmux_window"
        case tmuxPane = "tmux_pane"
        case requestId = "request_id"
        case tool
        case toolInput = "tool_input"
        case markdown
        case question, options
        case event
        case terminalEnv = "terminal_env"
        case subagentParentId = "subagent_parent_id"
        case tty, cwd
    }
}
```

- [ ] **Step 4: Build and verify compilation**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme MissionControl -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add MissionControl/MissionControl/Models.swift MissionControl/MissionControl/SocketMessage.swift
git commit -m "feat: extend Agent model and socket protocol for Vibe Island parity

Add TerminalEnv struct for env var collection, subagent tracking fields,
and event/tty/cwd fields to IncomingMessage."
```

---

## Task 2: Handle New Hook Events in AgentStore

**Files:**
- Modify: `MissionControl/MissionControl/AgentStore.swift`
- Modify: `MissionControl/MissionControl/MCSocketServer.swift`

- [ ] **Step 1: Add new message types to IncomingMessageType**

In `SocketMessage.swift`, add new cases:

```swift
enum IncomingMessageType: String, Codable {
    case statusUpdate = "status_update"
    case permissionRequest = "permission_request"
    case planReview = "plan_review"
    case question = "question"
    case questionResolved = "question_resolved"
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case subagentStart = "subagent_start"
    case subagentStop = "subagent_stop"
    case notification = "notification"
    case preCompact = "pre_compact"
}
```

- [ ] **Step 2: Add socket server handlers for new message types**

In `MCSocketServer.swift`, add new handler callbacks:

```swift
    var onSessionStart: ((IncomingMessage) -> Void)?
    var onSessionEnd: ((IncomingMessage) -> Void)?
    var onSubagentStart: ((IncomingMessage) -> Void)?
    var onSubagentStop: ((IncomingMessage) -> Void)?
    var onNotification: ((IncomingMessage) -> Void)?
    var onPreCompact: ((IncomingMessage) -> Void)?
```

Update `handleMessage` to dispatch new types:

```swift
    private func handleMessage(_ msg: IncomingMessage, from fd: Int32) {
        switch msg.type {
        case .statusUpdate:
            onStatusUpdate?(msg)
        case .permissionRequest:
            onPermissionRequest?(msg, fd)
        case .planReview:
            onPlanReview?(msg, fd)
        case .question:
            onQuestion?(msg, fd)
        case .questionResolved:
            onQuestionResolved?(msg)
        case .sessionStart:
            onSessionStart?(msg)
        case .sessionEnd:
            onSessionEnd?(msg)
        case .subagentStart:
            onSubagentStart?(msg)
        case .subagentStop:
            onSubagentStop?(msg)
        case .notification:
            onNotification?(msg)
        case .preCompact:
            onPreCompact?(msg)
        }
    }
```

- [ ] **Step 3: Implement handlers in AgentStore**

In `AgentStore.swift`, add handler implementations in `setupSocketServer()`:

```swift
        socketServer.onSessionStart = { [weak self] msg in
            self?.handleSessionStart(msg)
        }
        socketServer.onSessionEnd = { [weak self] msg in
            self?.handleSessionEnd(msg)
        }
        socketServer.onSubagentStart = { [weak self] msg in
            self?.handleSubagentStart(msg)
        }
        socketServer.onSubagentStop = { [weak self] msg in
            self?.handleSubagentStop(msg)
        }
        socketServer.onNotification = { [weak self] msg in
            self?.handleNotification(msg)
        }
        socketServer.onPreCompact = { [weak self] msg in
            self?.handlePreCompact(msg)
        }
```

Add the handler methods:

```swift
    // MARK: - New Hook Event Handlers

    private func handleSessionStart(_ msg: IncomingMessage) {
        guard let agentId = msg.agentId else { return }
        // Create new agent card or update existing
        if agents.firstIndex(where: { $0.id == agentId }) == nil {
            var agent = Agent(
                id: agentId,
                name: msg.name ?? agentId,
                status: .running,
                task: msg.task ?? "Starting...",
                summary: "",
                terminalLines: [],
                nextAction: "",
                updatedAt: Date(),
                worktree: msg.worktree ?? msg.cwd,
                app: msg.app,
                tmuxSession: msg.tmuxSession,
                tmuxWindow: msg.tmuxWindow,
                tmuxPane: msg.tmuxPane,
                agentType: msg.agentType
            )
            agent.terminalEnv = msg.terminalEnv
            agent.tty = msg.tty
            withAnimation(.easeInOut(duration: 0.2)) {
                agents.append(agent)
            }
        } else {
            // Session restart — update env and mark running
            if let idx = agents.firstIndex(where: { $0.id == agentId }) {
                agents[idx].terminalEnv = msg.terminalEnv
                agents[idx].tty = msg.tty
                if let name = msg.name { agents[idx].name = name }
                agents[idx].status = .running
                agents[idx].updatedAt = Date()
            }
        }
    }

    private func handleSessionEnd(_ msg: IncomingMessage) {
        guard let agentId = msg.agentId else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            agents.removeAll { $0.id == agentId }
        }
    }

    private func handleSubagentStart(_ msg: IncomingMessage) {
        guard let agentId = msg.agentId else { return }
        var agent = Agent(
            id: agentId,
            name: msg.name ?? "Sub-agent",
            status: .running,
            task: msg.task ?? "Working...",
            summary: "",
            terminalLines: [],
            nextAction: "",
            updatedAt: Date(),
            worktree: msg.worktree ?? msg.cwd,
            app: msg.app,
            agentType: msg.agentType
        )
        agent.subagentParentId = msg.subagentParentId
        agent.terminalEnv = msg.terminalEnv
        withAnimation(.easeInOut(duration: 0.2)) {
            agents.append(agent)
        }
    }

    private func handleSubagentStop(_ msg: IncomingMessage) {
        guard let agentId = msg.agentId else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            agents.removeAll { $0.id == agentId }
        }
    }

    private func handleNotification(_ msg: IncomingMessage) {
        guard let agentId = msg.agentId else { return }
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            if let task = msg.task { agents[idx].task = task }
            if let summary = msg.summary { agents[idx].summary = summary }
            agents[idx].updatedAt = Date()
        }
    }

    private func handlePreCompact(_ msg: IncomingMessage) {
        guard let agentId = msg.agentId else { return }
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            agents[idx].task = "Compacting context..."
            agents[idx].updatedAt = Date()
        }
    }
```

- [ ] **Step 4: Update handleStatusUpdate to store terminalEnv**

In `handleStatusUpdate`, after updating tmux fields, add:

```swift
                if let env = msg.terminalEnv { agents[idx].terminalEnv = env }
                if let tty = msg.tty { agents[idx].tty = tty }
                if let parentId = msg.subagentParentId { agents[idx].subagentParentId = parentId }
```

And in the new agent creation block:

```swift
            agent.terminalEnv = msg.terminalEnv
            agent.tty = msg.tty
            agent.subagentParentId = msg.subagentParentId
```

- [ ] **Step 5: Build and verify**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme MissionControl -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add MissionControl/MissionControl/AgentStore.swift MissionControl/MissionControl/MCSocketServer.swift MissionControl/MissionControl/SocketMessage.swift
git commit -m "feat: handle all 12 hook event types

Add SessionStart/End, SubagentStart/Stop, Notification, PreCompact
handlers. Store terminalEnv from all incoming messages."
```

---

## Task 3: Build Swift Bridge Binary

**Files:**
- Create: `MissionControl/Bridge/main.swift`
- Create: `MissionControl/Bridge/SocketClient.swift`
- Create: `MissionControl/Bridge/EnvCollector.swift`
- Create: `MissionControl/Bridge/HookRouter.swift`
- Create: `MissionControl/Bridge/BridgeModels.swift`
- Modify: `MissionControl/project.yml`

- [ ] **Step 1: Create Bridge directory**

```bash
mkdir -p /Users/kochunlong/MissionControl/MissionControl/Bridge
```

- [ ] **Step 2: Create BridgeModels.swift**

Create `MissionControl/Bridge/BridgeModels.swift`:

```swift
import Foundation

struct BridgeMessage: Codable {
    var type: String
    var agent_id: String?
    var agent_type: String?
    var name: String?
    var status: String?
    var task: String?
    var summary: String?
    var next_action: String?
    var worktree: String?
    var app: String?
    var tmux_session: String?
    var tmux_window: Int?
    var tmux_pane: Int?
    var request_id: String?
    var tool: String?
    var tool_input: [String: String]?
    var markdown: String?
    var question: String?
    var options: [[String: String]]?
    var event: String?
    var terminal_env: [String: String]?
    var subagent_parent_id: String?
    var tty: String?
    var cwd: String?
}

struct BridgeResponse: Codable {
    var type: String?
    var request_id: String?
    var decision: String?
}
```

- [ ] **Step 3: Create EnvCollector.swift**

Create `MissionControl/Bridge/EnvCollector.swift`:

```swift
import Foundation

struct EnvCollector {
    static let envKeys = [
        "ITERM_SESSION_ID",
        "TERM_SESSION_ID",
        "TERM_PROGRAM",
        "TMUX",
        "TMUX_PANE",
        "KITTY_WINDOW_ID",
        "__CFBundleIdentifier",
        "CMUX_WORKSPACE_ID",
        "CMUX_SURFACE_ID",
        "CMUX_SOCKET_PATH",
    ]

    static func collect() -> [String: String] {
        var result: [String: String] = [:]
        for key in envKeys {
            if let value = ProcessInfo.processInfo.environment[key] {
                result[key] = value
            }
        }
        return result
    }

    static func detectApp() -> String {
        let bundleId = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? ""
        let mapping: [String: String] = [
            "com.apple.Terminal": "Terminal",
            "com.google.antigravity": "Antigravity",
            "com.mitchellh.ghostty": "Ghostty",
            "com.microsoft.VSCode": "VS Code",
            "com.todesktop.runtime.cursor": "Cursor",
            "dev.warp.Warp-Stable": "Warp",
            "net.kovidgoyal.kitty": "Kitty",
        ]
        if let name = mapping[bundleId] { return name }
        if !bundleId.isEmpty {
            return bundleId.split(separator: ".").last.map(String.init)?.capitalized ?? "Terminal"
        }
        return "Terminal"
    }

    static func detectTmux() -> (session: String?, window: Int, pane: Int) {
        guard ProcessInfo.processInfo.environment["TMUX"] != nil else {
            return (nil, 0, 0)
        }
        func tmuxQuery(_ format: String) -> String? {
            let process = Process()
            let tmuxPaths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            guard let tmuxPath = tmuxPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                return nil
            }
            process.executableURL = URL(fileURLWithPath: tmuxPath)
            process.arguments = ["display-message", "-p", format]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        let session = tmuxQuery("#{session_name}")
        let window = Int(tmuxQuery("#{window_index}") ?? "0") ?? 0
        let pane = Int(tmuxQuery("#{pane_index}") ?? "0") ?? 0
        return (session, window, pane)
    }

    static func tty() -> String? {
        if isatty(STDIN_FILENO) != 0 {
            return String(cString: ttyname(STDIN_FILENO))
        }
        // Try from env
        return ProcessInfo.processInfo.environment["TTY"]
    }

    static func projectName(cwd: String) -> String {
        // Try git branch first
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd, "branch", "--show-current"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            var branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !branch.isEmpty {
                if let slashIdx = branch.firstIndex(of: "/") {
                    branch = String(branch[branch.index(after: slashIdx)...])
                }
                return branch.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            }
        } catch {}
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}
```

- [ ] **Step 4: Create SocketClient.swift**

Create `MissionControl/Bridge/SocketClient.swift`:

```swift
import Foundation

struct SocketClient {
    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.mission-control/mc.sock"
    }()

    /// Send a message and optionally wait for response.
    /// Returns nil if fire-and-forget or on error.
    static func send(_ message: BridgeMessage, waitForResponse: Bool = false, timeout: TimeInterval = 86400) -> BridgeResponse? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { if !waitForResponse { close(fd) } }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: 104) { ptr in
                    _ = strncpy(ptr, src, 103)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { close(fd); return nil }

        // Encode and send
        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(message) else { close(fd); return nil }
        data.append(0x0A) // newline delimiter
        let sent = data.withUnsafeBytes { ptr -> Int in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return Darwin.send(fd, baseAddress, data.count, 0)
        }
        guard sent == data.count else { close(fd); return nil }

        if !waitForResponse {
            close(fd)
            return nil
        }

        // Wait for response
        // Set socket timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buffer = Data()
        var rawBuffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = recv(fd, &rawBuffer, rawBuffer.count, 0)
            if bytesRead <= 0 { break }
            buffer.append(contentsOf: rawBuffer[0..<bytesRead])
            if buffer.contains(0x0A) { break }
        }
        close(fd)

        guard let newlineIdx = buffer.firstIndex(of: 0x0A) else {
            return BridgeResponse(decision: "approve")
        }
        let lineData = buffer[buffer.startIndex..<newlineIdx]
        return try? JSONDecoder().decode(BridgeResponse.self, from: Data(lineData))
    }
}
```

- [ ] **Step 5: Create HookRouter.swift**

Create `MissionControl/Bridge/HookRouter.swift`:

```swift
import Foundation

struct HookRouter {
    let source: String
    let event: String
    let hookInput: [String: Any]

    func route() {
        let agentId = deriveAgentId()
        let env = EnvCollector.collect()
        let app = EnvCollector.detectApp()
        let tmux = EnvCollector.detectTmux()
        let cwd = hookInput["cwd"] as? String ?? ""
        let sessionId = hookInput["session_id"] as? String ?? ""
        let name = EnvCollector.projectName(cwd: cwd)
        let tty = EnvCollector.tty()

        switch event.lowercased() {
        case "sessionstart":
            let msg = BridgeMessage(
                type: "session_start", agent_id: agentId, agent_type: source,
                name: name, status: "running", worktree: cwd, app: app,
                tmux_session: tmux.session, tmux_window: tmux.session != nil ? tmux.window : nil,
                tmux_pane: tmux.session != nil ? tmux.pane : nil,
                event: event, terminal_env: env, tty: tty, cwd: cwd
            )
            _ = SocketClient.send(msg)

        case "sessionend":
            let msg = BridgeMessage(
                type: "session_end", agent_id: agentId, event: event
            )
            _ = SocketClient.send(msg)

        case "userpromptsubmit":
            let msg = BridgeMessage(
                type: "status_update", agent_id: agentId, agent_type: source,
                name: name, status: "running", task: "Processing...",
                worktree: cwd, app: app,
                tmux_session: tmux.session, tmux_window: tmux.session != nil ? tmux.window : nil,
                tmux_pane: tmux.session != nil ? tmux.pane : nil,
                event: event, terminal_env: env, tty: tty, cwd: cwd
            )
            _ = SocketClient.send(msg)

        case "pretooluse":
            let toolName = hookInput["tool_name"] as? String ?? "tool"
            let msg = BridgeMessage(
                type: "status_update", agent_id: agentId,
                status: "running", task: "Using \(toolName)...",
                event: event, terminal_env: env
            )
            _ = SocketClient.send(msg)

        case "posttooluse":
            // Clear pending question + mark running
            let clearMsg = BridgeMessage(type: "question_resolved", agent_id: agentId)
            _ = SocketClient.send(clearMsg)
            let msg = BridgeMessage(
                type: "status_update", agent_id: agentId, status: "running",
                event: event, terminal_env: env
            )
            _ = SocketClient.send(msg)

        case "notification":
            let notification = hookInput["message"] as? String ?? ""
            let msg = BridgeMessage(
                type: "notification", agent_id: agentId,
                summary: notification, event: event
            )
            _ = SocketClient.send(msg)

        case "stop":
            handleStop(agentId: agentId, name: name, cwd: cwd, app: app, tmux: tmux, env: env, tty: tty)

        case "subagentstart":
            let parentSessionId = hookInput["parent_session_id"] as? String
            let parentId = parentSessionId.map { String($0.prefix(8)) }
            let msg = BridgeMessage(
                type: "subagent_start", agent_id: agentId, agent_type: source,
                name: "Sub-agent", status: "running",
                worktree: cwd, app: app,
                event: event, terminal_env: env, subagent_parent_id: parentId, cwd: cwd
            )
            _ = SocketClient.send(msg)

        case "subagentstop":
            let msg = BridgeMessage(
                type: "subagent_stop", agent_id: agentId, event: event
            )
            _ = SocketClient.send(msg)

        case "precompact":
            let msg = BridgeMessage(
                type: "pre_compact", agent_id: agentId, event: event
            )
            _ = SocketClient.send(msg)

        case "permissionrequest":
            handlePermission(agentId: agentId, tmux: tmux, env: env, name: name)

        default:
            // Unknown event — send as generic status update
            let msg = BridgeMessage(
                type: "status_update", agent_id: agentId,
                event: event, terminal_env: env
            )
            _ = SocketClient.send(msg)
        }
    }

    private func deriveAgentId() -> String {
        let sessionId = hookInput["session_id"] as? String ?? ""
        if !sessionId.isEmpty {
            return String(sessionId.prefix(8))
        }
        let cwd = hookInput["cwd"] as? String ?? ""
        let data = Data(cwd.utf8)
        // Simple hash
        var hash: UInt64 = 5381
        for byte in data { hash = hash &* 33 &+ UInt64(byte) }
        return String(format: "%08x", UInt32(hash & 0xFFFFFFFF))
    }

    private func handleStop(agentId: String, name: String, cwd: String, app: String,
                            tmux: (session: String?, window: Int, pane: Int),
                            env: [String: String], tty: String?) {
        let lastMessage = hookInput["last_assistant_message"] as? String ?? ""
        let stopReason = hookInput["stop_reason"] as? String ?? ""

        // Naive status detection
        var status = "running"
        let msgLower = lastMessage.lowercased()
        let questionSignals = ["?", "？", "which option", "do you want", "should i",
                               "please choose", "你想", "你觉得", "请选择", "你選"]
        if questionSignals.contains(where: { msgLower.contains($0) }) {
            status = "blocked"
        }
        if stopReason == "tool_use" { status = "blocked" }
        if msgLower.contains("done") || msgLower.contains("complete") || msgLower.contains("完成") {
            status = "done"
        }

        // Truncate for display
        let lines = lastMessage.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count > 5 }
        let task = String((lines.first ?? "Working...").prefix(60))
        let summary = String(lines.prefix(3).joined(separator: " ").prefix(300))
        let nextAction = String((lines.last ?? "").prefix(200))

        let msg = BridgeMessage(
            type: "status_update", agent_id: agentId, agent_type: source,
            name: name, status: status, task: task, summary: summary,
            next_action: nextAction, worktree: cwd, app: app,
            tmux_session: tmux.session, tmux_window: tmux.session != nil ? tmux.window : nil,
            tmux_pane: tmux.session != nil ? tmux.pane : nil,
            event: "Stop", terminal_env: env, tty: tty, cwd: cwd
        )
        _ = SocketClient.send(msg)
    }

    private func handlePermission(agentId: String,
                                  tmux: (session: String?, window: Int, pane: Int),
                                  env: [String: String], name: String) {
        let toolName = hookInput["tool_name"] as? String ?? "Unknown"
        var toolInput: [String: String] = [:]
        if let raw = hookInput["tool_input"] as? [String: Any] {
            for (k, v) in raw {
                toolInput[k] = v as? String ?? "\(v)"
            }
        }
        let requestId = "perm_\(UUID().uuidString.prefix(12))"

        let msg = BridgeMessage(
            type: "permission_request", agent_id: agentId,
            name: name, app: EnvCollector.detectApp(),
            tmux_session: tmux.session, tmux_window: tmux.session != nil ? tmux.window : nil,
            tmux_pane: tmux.session != nil ? tmux.pane : nil,
            request_id: requestId, tool: toolName, tool_input: toolInput,
            terminal_env: env
        )

        let response = SocketClient.send(msg, waitForResponse: true, timeout: 86400)
        if let response = response, response.decision == "deny" {
            // Output denial for Claude Code to read
            let output = ["decision": "block", "reason": "User denied in MissionControl"]
            if let data = try? JSONSerialization.data(withJSONObject: output),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("{\"approve\":true}")
        }
    }
}
```

- [ ] **Step 6: Create main.swift**

Create `MissionControl/Bridge/main.swift`:

```swift
import Foundation

// mc-bridge: compiled Swift bridge for MissionControl
// Usage: mc-bridge --source claude --event Stop [--cwd /path]
// Reads hook JSON from stdin, collects env vars, sends to socket.

func parseArgs() -> (source: String, event: String, cwd: String?) {
    var source = "claude"
    var event = ""
    var cwd: String? = nil
    let args = CommandLine.arguments

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--source":
            i += 1; if i < args.count { source = args[i] }
        case "--event":
            i += 1; if i < args.count { event = args[i] }
        case "--cwd":
            i += 1; if i < args.count { cwd = args[i] }
        default:
            break
        }
        i += 1
    }
    return (source, event, cwd)
}

func readStdin() -> [String: Any] {
    var input = ""
    while let line = readLine(strippingNewline: false) {
        input += line
    }
    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return [:]
    }
    guard let data = input.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return json
}

let (source, event, cwdArg) = parseArgs()

guard !event.isEmpty else {
    fputs("Usage: mc-bridge --source <source> --event <event> [--cwd <path>]\n", stderr)
    exit(1)
}

var hookInput = readStdin()
if let cwd = cwdArg {
    hookInput["cwd"] = cwd
}

let router = HookRouter(source: source, event: event, hookInput: hookInput)
router.route()
```

- [ ] **Step 7: Add mc-bridge target to project.yml**

Add to `project.yml`:

```yaml
  mc-bridge:
    type: tool
    platform: macOS
    sources:
      - path: MissionControl/Bridge
    settings:
      base:
        PRODUCT_NAME: mc-bridge
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.9"
    postBuildScripts:
      - script: |
          mkdir -p "${PROJECT_DIR}/MissionControl/Helpers"
          cp "${BUILT_PRODUCTS_DIR}/mc-bridge" "${PROJECT_DIR}/MissionControl/Helpers/mc-bridge"
        name: "Copy bridge binary"
```

- [ ] **Step 8: Build bridge target**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme mc-bridge -configuration Release build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Create launcher shim**

Create `MissionControl/cli/bin/mc-bridge` (shell script):

```bash
#!/bin/bash
# mc-bridge launcher shim — finds and runs the compiled bridge binary

BINARY_NAME="mc-bridge"
CACHE_FILE="$HOME/.mission-control/.bridge-cache"

# 1. Try direct paths
for APP_PATH in \
    "/Applications/MissionControl.app/Contents/Helpers/$BINARY_NAME" \
    "$HOME/Desktop/MissionControl.app/Contents/Helpers/$BINARY_NAME" \
    "$HOME/Applications/MissionControl.app/Contents/Helpers/$BINARY_NAME"; do
    if [ -x "$APP_PATH" ]; then
        exec "$APP_PATH" "$@"
    fi
done

# 2. Try cache
if [ -f "$CACHE_FILE" ]; then
    CACHED=$(cat "$CACHE_FILE")
    if [ -x "$CACHED" ]; then
        exec "$CACHED" "$@"
    fi
fi

# 3. Try Spotlight
FOUND=$(mdfind "kMDItemCFBundleIdentifier == 'com.missioncontrol.app'" 2>/dev/null | head -1)
if [ -n "$FOUND" ] && [ -x "$FOUND/Contents/Helpers/$BINARY_NAME" ]; then
    echo "$FOUND/Contents/Helpers/$BINARY_NAME" > "$CACHE_FILE"
    exec "$FOUND/Contents/Helpers/$BINARY_NAME" "$@"
fi

# 4. Fallback: try Python bridge
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/hooks"
if [ -f "$SCRIPT_DIR/mc-bridge.py" ]; then
    exec python3 "$SCRIPT_DIR/mc-bridge.py" "$@"
fi

echo "mc-bridge: binary not found" >&2
exit 1
```

Make executable: `chmod +x /Users/kochunlong/MissionControl/cli/bin/mc-bridge`

- [ ] **Step 10: Commit**

```bash
git add MissionControl/Bridge/ MissionControl/cli/bin/mc-bridge project.yml
git commit -m "feat: compiled Swift bridge binary replacing Python hooks

Universal binary (arm64+x86_64) for all hook events. Two modes:
fire-and-forget for status updates, blocking for PermissionRequest
(86400s timeout). Includes env var collection and launcher shim."
```

---

## Task 4: Update Hook Installation to Use Bridge Binary

**Files:**
- Modify: `MissionControl/cli/bin/cli.mjs`

- [ ] **Step 1: Update HOOK_CONFIG to use mc-bridge binary**

Replace the `HOOK_CONFIG` constant and add new hook events:

```javascript
const BRIDGE_CMD = `${join(MC_DIR, 'bin', 'mc-bridge')}`;

const HOOK_CONFIG = {
  hooks: {
    SessionStart: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event SessionStart` }],
      },
    ],
    SessionEnd: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event SessionEnd` }],
      },
    ],
    UserPromptSubmit: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event UserPromptSubmit` }],
      },
    ],
    PreToolUse: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event PreToolUse` }],
      },
    ],
    PostToolUse: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event PostToolUse` }],
      },
    ],
    Notification: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event Notification` }],
      },
    ],
    Stop: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event Stop` }],
      },
    ],
    SubagentStart: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event SubagentStart` }],
      },
    ],
    SubagentStop: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event SubagentStop` }],
      },
    ],
    PreCompact: [
      {
        matcher: '',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event PreCompact` }],
      },
    ],
    PermissionRequest: [
      {
        matcher: '*',
        hooks: [{ type: 'command', command: `${BRIDGE_CMD} --source claude --event PermissionRequest`, timeout: 86400 }],
      },
    ],
  },
};
```

- [ ] **Step 2: Update setup to install bridge binary and shim**

Add to the `setup()` function, after hook file installation:

```javascript
  // Install bridge binary shim
  const shimSrc = join(__dirname, 'mc-bridge');
  const shimDest = join(MC_DIR, 'bin', 'mc-bridge');
  mkdirSync(join(MC_DIR, 'bin'), { recursive: true });
  copyFileSync(shimSrc, shimDest);
  try { execSync(`chmod +x "${shimDest}"`, { stdio: 'pipe' }); } catch {}
  console.log('  ✓ Installed mc-bridge launcher shim');
```

- [ ] **Step 3: Update isManagedMissionControlCommand to detect new bridge commands**

```javascript
function isManagedMissionControlCommand(command) {
  if (!command) return false;
  // Match both old Python hooks and new bridge commands
  return missionControlHookPaths().some((hookPath) => command.includes(hookPath))
    || command.includes('mc-bridge')
    || command.includes('mission-control');
}
```

- [ ] **Step 4: Commit**

```bash
git add MissionControl/cli/bin/cli.mjs
git commit -m "feat: update hook installer for 12 events + bridge binary

All hook events now use compiled mc-bridge binary.
PermissionRequest timeout increased to 86400s (24h)."
```

---

## Task 5: Terminal Jumping Engine — Protocol + Generic/Tmux

**Files:**
- Create: `MissionControl/MissionControl/Jumping/TerminalJumper.swift`
- Create: `MissionControl/MissionControl/Jumping/JumpEngine.swift`
- Create: `MissionControl/MissionControl/Jumping/GenericJumper.swift`
- Create: `MissionControl/MissionControl/Jumping/TmuxJumper.swift`

- [ ] **Step 1: Create Jumping directory**

```bash
mkdir -p /Users/kochunlong/MissionControl/MissionControl/Jumping
```

- [ ] **Step 2: Create TerminalJumper.swift**

```swift
import Foundation

protocol TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool
    static func jump(env: TerminalEnv, agent: Agent) async throws
}

enum JumpError: Error {
    case noTerminalInfo
    case appleScriptFailed(String)
    case processNotFound
}
```

- [ ] **Step 3: Create GenericJumper.swift**

```swift
import AppKit

struct GenericJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        // Always matches as last resort
        true
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        // Use AXRaise via AppleScript on the app
        let appName = agent.displayApp
        let script = """
        tell application "\(appName)"
            activate
        end tell
        tell application "System Events"
            tell process "\(appName)"
                set frontmost to true
                try
                    perform action "AXRaise" of window 1
                end try
            end tell
        end tell
        """
        try await runAppleScript(script)
    }

    static func runAppleScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                var errorDict: NSDictionary?
                let appleScript = NSAppleScript(source: source)
                appleScript?.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: JumpError.appleScriptFailed(msg))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
```

- [ ] **Step 4: Create TmuxJumper.swift**

```swift
import Foundation

struct TmuxJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.tmux != nil && env.tmuxPane != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let tmuxTarget = agent.tmuxTarget else {
            throw JumpError.noTerminalInfo
        }

        // Select the tmux window and pane
        let tmuxPath = findTmuxBinary()
        await runTmux(tmuxPath, args: ["select-window", "-t", tmuxTarget])
        await runTmux(tmuxPath, args: ["select-pane", "-t", tmuxTarget])

        // Raise the host terminal window
        try await GenericJumper.jump(env: env, agent: agent)
    }

    private static func findTmuxBinary() -> String {
        let paths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        return paths.first { FileManager.default.fileExists(atPath: $0) } ?? "tmux"
    }

    @discardableResult
    private static func runTmux(_ path: String, args: [String]) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 5: Create JumpEngine.swift**

```swift
import Foundation

struct JumpEngine {
    static let jumpers: [TerminalJumper.Type] = [
        ITermJumper.self,
        GhosttyJumper.self,
        TerminalAppJumper.self,
        VSCodeJumper.self,
        KittyJumper.self,
        WarpJumper.self,
        CmuxJumper.self,
        TmuxJumper.self,
        GenericJumper.self,
    ]

    static func jump(to agent: Agent) async {
        let env = agent.terminalEnv ?? TerminalEnv()
        for jumper in jumpers {
            if jumper.canHandle(env: env) {
                do {
                    try await jumper.jump(env: env, agent: agent)
                } catch {
                    print("JumpEngine: \(type(of: jumper)) failed: \(error), trying next...")
                    continue
                }
                return
            }
        }
    }
}
```

- [ ] **Step 6: Build (will have compile errors for unimplemented jumpers — add stubs)**

Create placeholder files so compilation passes. Each file follows this pattern:

`MissionControl/MissionControl/Jumping/ITermJumper.swift`:
```swift
import Foundation

struct ITermJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.itermSessionId != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        // TODO: implement in Task 6
        try await GenericJumper.jump(env: env, agent: agent)
    }
}
```

Create similar stubs for: `GhosttyJumper.swift`, `TerminalAppJumper.swift`, `VSCodeJumper.swift`, `KittyJumper.swift`, `WarpJumper.swift`, `CmuxJumper.swift`.

`GhosttyJumper.swift`:
```swift
import Foundation

struct GhosttyJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        let prog = env.termProgram?.lowercased() ?? ""
        return prog == "ghostty" || prog == "xterm-ghostty"
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        try await GenericJumper.jump(env: env, agent: agent)
    }
}
```

`TerminalAppJumper.swift`:
```swift
import Foundation

struct TerminalAppJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.termSessionId != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        try await GenericJumper.jump(env: env, agent: agent)
    }
}
```

`VSCodeJumper.swift`:
```swift
import Foundation

struct VSCodeJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        let bundle = env.cfBundleIdentifier?.lowercased() ?? ""
        return bundle.contains("vscode") || bundle.contains("cursor") || bundle.contains("windsurf")
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        try await GenericJumper.jump(env: env, agent: agent)
    }
}
```

`KittyJumper.swift`:
```swift
import Foundation

struct KittyJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.kittyWindowId != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        try await GenericJumper.jump(env: env, agent: agent)
    }
}
```

`WarpJumper.swift`:
```swift
import Foundation

struct WarpJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.termProgram?.lowercased() == "warpterminal"
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        try await GenericJumper.jump(env: env, agent: agent)
    }
}
```

`CmuxJumper.swift`:
```swift
import Foundation

struct CmuxJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.cmuxSocketPath != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        try await GenericJumper.jump(env: env, agent: agent)
    }
}
```

- [ ] **Step 7: Build and verify**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme MissionControl -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add MissionControl/MissionControl/Jumping/
git commit -m "feat: terminal jumping engine with protocol + stub jumpers

JumpEngine iterates jumpers by priority. GenericJumper (AXRaise) and
TmuxJumper fully implemented. Other jumpers stubbed for Task 6."
```

---

## Task 6: Implement Per-Terminal Jumping Strategies

**Files:**
- Modify: `MissionControl/MissionControl/Jumping/ITermJumper.swift`
- Modify: `MissionControl/MissionControl/Jumping/GhosttyJumper.swift`
- Modify: `MissionControl/MissionControl/Jumping/TerminalAppJumper.swift`
- Modify: `MissionControl/MissionControl/Jumping/VSCodeJumper.swift`
- Modify: `MissionControl/MissionControl/Jumping/KittyJumper.swift`
- Modify: `MissionControl/MissionControl/Jumping/WarpJumper.swift`
- Modify: `MissionControl/MissionControl/Jumping/CmuxJumper.swift`

- [ ] **Step 1: Implement ITermJumper**

Replace `MissionControl/MissionControl/Jumping/ITermJumper.swift`:

```swift
import AppKit

struct ITermJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.itermSessionId != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let sessionId = env.itermSessionId else {
            throw JumpError.noTerminalInfo
        }

        // Parse session ID: format is "wXtYpZ" (window X, tab Y, pane Z)
        // or just a unique identifier
        let script = """
        tell application "iTerm2"
            activate
            repeat with aWin in windows
                tell aWin
                    repeat with aTab in tabs
                        tell aTab
                            repeat with aSession in sessions
                                tell aSession
                                    if (variable named "session.uniqueID") contains "\(sessionId)" then
                                        select
                                        set selected tab of aWin to aTab
                                        tell application "System Events"
                                            tell process "iTerm2"
                                                perform action "AXRaise" of window 1
                                            end tell
                                        end tell
                                        return
                                    end if
                                end tell
                            end repeat
                        end tell
                    end repeat
                end tell
            end repeat
        end tell
        """
        try await GenericJumper.runAppleScript(script)
    }
}
```

- [ ] **Step 2: Implement TerminalAppJumper**

Replace `MissionControl/MissionControl/Jumping/TerminalAppJumper.swift`:

```swift
import AppKit

struct TerminalAppJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.termSessionId != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let sessionId = env.termSessionId else {
            throw JumpError.noTerminalInfo
        }

        let script = """
        tell application "Terminal"
            activate
            repeat with aWin in windows
                repeat with aTab in tabs of aWin
                    if tty of aTab contains "\(sessionId)" then
                        set selected tab of aWin to aTab
                        set index of aWin to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        try await GenericJumper.runAppleScript(script)
    }
}
```

- [ ] **Step 3: Implement KittyJumper**

Replace `MissionControl/MissionControl/Jumping/KittyJumper.swift`:

```swift
import Foundation

struct KittyJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.kittyWindowId != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let windowId = env.kittyWindowId else {
            throw JumpError.noTerminalInfo
        }

        let kittyPaths = ["/opt/homebrew/bin/kitty", "/usr/local/bin/kitty", "/Applications/kitty.app/Contents/MacOS/kitty"]
        guard let kittyPath = kittyPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            try await GenericJumper.jump(env: env, agent: agent)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kittyPath)
        process.arguments = ["@", "focus-window", "--match", "id:\(windowId)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // Also activate the Kitty app
        try await GenericJumper.jump(env: env, agent: agent)
    }
}
```

- [ ] **Step 4: Implement VSCodeJumper**

Replace `MissionControl/MissionControl/Jumping/VSCodeJumper.swift`:

```swift
import AppKit

struct VSCodeJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        let bundle = env.cfBundleIdentifier?.lowercased() ?? ""
        return bundle.contains("vscode") || bundle.contains("cursor") || bundle.contains("windsurf")
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        // Determine the URI scheme based on the app
        let bundle = env.cfBundleIdentifier?.lowercased() ?? ""
        let scheme: String
        if bundle.contains("cursor") {
            scheme = "cursor"
        } else if bundle.contains("windsurf") {
            scheme = "windsurf"
        } else {
            scheme = "vscode"
        }

        // Try URI handler if VSIX extension is installed
        let tty = agent.tty ?? ""
        let url = "\(scheme)://missioncontrol.terminal-focus/jump?tty=\(tty)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Fallback to just activating the app
            try await GenericJumper.jump(env: env, agent: agent)
        }
    }
}
```

- [ ] **Step 5: Implement WarpJumper**

Replace `MissionControl/MissionControl/Jumping/WarpJumper.swift`:

```swift
import AppKit

struct WarpJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.termProgram?.lowercased() == "warpterminal"
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        // Warp doesn't have a tab API — activate and AXRaise
        let script = """
        tell application "Warp"
            activate
        end tell
        tell application "System Events"
            tell process "Warp"
                set frontmost to true
                try
                    perform action "AXRaise" of window 1
                end try
            end tell
        end tell
        """
        try await GenericJumper.runAppleScript(script)
    }
}
```

- [ ] **Step 6: Implement GhosttyJumper**

Replace `MissionControl/MissionControl/Jumping/GhosttyJumper.swift`:

```swift
import AppKit

struct GhosttyJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        let prog = env.termProgram?.lowercased() ?? ""
        return prog == "ghostty" || prog == "xterm-ghostty"
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        // Ghostty uses AppleScript for window activation
        // Tab matching uses the OSC2 title set by the bridge
        let script = """
        tell application "Ghostty"
            activate
        end tell
        tell application "System Events"
            tell process "Ghostty"
                set frontmost to true
                try
                    perform action "AXRaise" of window 1
                end try
            end tell
        end tell
        """
        try await GenericJumper.runAppleScript(script)
    }
}
```

- [ ] **Step 7: Implement CmuxJumper**

Replace `MissionControl/MissionControl/Jumping/CmuxJumper.swift`:

```swift
import Foundation

struct CmuxJumper: TerminalJumper {
    static func canHandle(env: TerminalEnv) -> Bool {
        env.cmuxSocketPath != nil
    }

    static func jump(env: TerminalEnv, agent: Agent) async throws {
        guard let socketPath = env.cmuxSocketPath,
              let surfaceId = env.cmuxSurfaceId else {
            try await GenericJumper.jump(env: env, agent: agent)
            return
        }

        // Send JSON-RPC focus command via cmux socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            try await GenericJumper.jump(env: env, agent: agent)
            return
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: 104) { ptr in
                    _ = strncpy(ptr, src, 103)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            try await GenericJumper.jump(env: env, agent: agent)
            return
        }

        let rpc = "{\"method\":\"focus\",\"params\":{\"surface\":\"\(surfaceId)\"}}\n"
        _ = rpc.withCString { ptr in
            send(fd, ptr, strlen(ptr), 0)
        }
    }
}
```

- [ ] **Step 8: Wire JumpEngine into AgentStore**

In `AgentStore.swift`, replace the existing tmux-based jump logic. Add a method:

```swift
    func jumpToAgent(_ agent: Agent) {
        Task {
            await JumpEngine.jump(to: agent)
        }
    }
```

- [ ] **Step 9: Build and verify**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme MissionControl -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add MissionControl/MissionControl/Jumping/ MissionControl/MissionControl/AgentStore.swift
git commit -m "feat: implement per-terminal jumping strategies

iTerm2 (AppleScript session match), Terminal.app, Kitty (remote control),
VS Code/Cursor (URI handler), Warp, Ghostty, cmux (JSON-RPC).
JumpEngine wired into AgentStore.jumpToAgent()."
```

---

## Task 7: Notch UI — NotchPanel + NotchDetector

**Files:**
- Create: `MissionControl/MissionControl/UI/NotchDetector.swift`
- Create: `MissionControl/MissionControl/UI/NotchPanel.swift`
- Modify: `MissionControl/MissionControl/MissionControlApp.swift`
- Modify: `MissionControl/MissionControl/FloatingPanel.swift`

- [ ] **Step 1: Create UI directory**

```bash
mkdir -p /Users/kochunlong/MissionControl/MissionControl/UI
```

- [ ] **Step 2: Create NotchDetector.swift**

```swift
import AppKit

struct NotchDetector {
    static func hasNotch(screen: NSScreen) -> Bool {
        // macOS 12+ notched MacBooks have auxiliaryTopLeftArea
        if #available(macOS 12.0, *) {
            return screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }
        return false
    }

    static func notchFrame(screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = frame.maxY - visibleFrame.maxY

        // Notch is centered at top of screen
        let notchWidth: CGFloat = 200
        return NSRect(
            x: frame.midX - notchWidth / 2,
            y: frame.maxY - menuBarHeight,
            width: notchWidth,
            height: menuBarHeight
        )
    }

    static func panelOrigin(for screen: NSScreen, panelSize: NSSize, isExpanded: Bool) -> NSPoint {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame

        if hasNotch(screen: screen) {
            // Position centered at top, aligned with notch
            let x = frame.midX - panelSize.width / 2
            let y = frame.maxY - panelSize.height
            return NSPoint(x: x, y: y)
        } else {
            // Non-notch: position at top center of visible frame
            let x = visibleFrame.midX - panelSize.width / 2
            let y = visibleFrame.maxY - panelSize.height
            return NSPoint(x: x, y: y)
        }
    }
}
```

- [ ] **Step 3: Create NotchPanel.swift**

```swift
import AppKit

class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar + 1  // Above menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let origin = NotchDetector.panelOrigin(
            for: screen,
            panelSize: frame.size,
            isExpanded: false
        )
        setFrameOrigin(origin)
    }
}
```

- [ ] **Step 4: Update MissionControlApp.swift to use NotchPanel**

Replace FloatingPanel with NotchPanel in `AppDelegate`:

```swift
    private var panel: NotchPanel!
```

Update `applicationDidFinishLaunching`:

```swift
        // Create the notch panel
        panel = NotchPanel()

        let hostingView = NSHostingView(rootView:
            ContentView()
                .environmentObject(store)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        // Position based on notch detection
        panel.reposition()

        // Re-center when panel resizes
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
            self?.panel.reposition()
        }

        // Handle screen changes (external display, etc.)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panel.reposition()
        }

        panel.orderFrontRegardless()
```

- [ ] **Step 5: Build and verify**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme MissionControl -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add MissionControl/MissionControl/UI/ MissionControl/MissionControl/MissionControlApp.swift
git commit -m "feat: notch-aware panel positioning

NotchDetector checks for MacBook notch via auxiliaryTopLeftArea.
NotchPanel positioned at notch level on notched Macs, top-center
on external displays. Auto-repositions on screen changes."
```

---

## Task 8: StatusLine Rate Limit Tracking

**Files:**
- Create: `MissionControl/MissionControl/RateLimitMonitor.swift`
- Create: `MissionControl/cli/bin/mc-statusline`
- Modify: `MissionControl/MissionControl/AgentStore.swift`

- [ ] **Step 1: Create mc-statusline script**

Create `MissionControl/cli/bin/mc-statusline`:

```bash
#!/bin/bash
# Extracts rate_limits from Claude Code statusLine JSON and caches to /tmp
INPUT=$(cat)
echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    rl = data.get('rate_limits', data.get('rateLimits', {}))
    if rl:
        json.dump(rl, open('/tmp/mc-rate-limits.json', 'w'))
except:
    pass
" 2>/dev/null
```

Make executable: `chmod +x /Users/kochunlong/MissionControl/cli/bin/mc-statusline`

- [ ] **Step 2: Create RateLimitMonitor.swift**

```swift
import Foundation
import Combine

@MainActor
class RateLimitMonitor: ObservableObject {
    @Published var rateLimits: RateLimits?

    struct RateLimits {
        var used5h: Int
        var limit5h: Int
        var used7d: Int
        var limit7d: Int

        var remaining5h: Int { limit5h - used5h }
        var remaining7d: Int { limit7d - used7d }
        var percent5h: Double { limit5h > 0 ? Double(remaining5h) / Double(limit5h) : 1.0 }
        var percent7d: Double { limit7d > 0 ? Double(remaining7d) / Double(limit7d) : 1.0 }
    }

    private let filePath = "/tmp/mc-rate-limits.json"
    private var fileMonitor: DispatchSourceFileSystemObject?

    func startMonitoring() {
        // Read initial value
        readFile()

        // Watch for changes using kqueue
        guard FileManager.default.fileExists(atPath: filePath) else {
            // Poll until file appears
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self = self else { timer.invalidate(); return }
                    if FileManager.default.fileExists(atPath: self.filePath) {
                        timer.invalidate()
                        self.readFile()
                        self.watchFile()
                    }
                }
            }
            return
        }
        watchFile()
    }

    func stopMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    private func watchFile() {
        let fd = open(filePath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.readFile()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileMonitor = source
    }

    private func readFile() {
        guard let data = FileManager.default.contents(atPath: filePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Parse — field names may vary, try common patterns
        let used5h = json["requestsUsed5h"] as? Int ?? json["used_5h"] as? Int ?? 0
        let limit5h = json["requestsLimit5h"] as? Int ?? json["limit_5h"] as? Int ?? 0
        let used7d = json["requestsUsed7d"] as? Int ?? json["used_7d"] as? Int ?? 0
        let limit7d = json["requestsLimit7d"] as? Int ?? json["limit_7d"] as? Int ?? 0

        rateLimits = RateLimits(used5h: used5h, limit5h: limit5h, used7d: used7d, limit7d: limit7d)
    }
}
```

- [ ] **Step 3: Add RateLimitMonitor to AgentStore**

In `AgentStore.swift`, add:

```swift
    let rateLimitMonitor = RateLimitMonitor()
```

In `startWatching()`, add:

```swift
        rateLimitMonitor.startMonitoring()
```

In `stopWatching()`, add:

```swift
        rateLimitMonitor.stopMonitoring()
```

- [ ] **Step 4: Update cli.mjs to install statusLine config**

In `setupClaudeCode()`, after writing hooks, add statusLine:

```javascript
  // Install statusLine for rate limit tracking
  if (!settings.statusLine) {
    settings.statusLine = `${join(MC_DIR, 'bin', 'mc-statusline')}`;
    console.log('  ✓ Configured statusLine for rate limit tracking');
  }
```

Also install the mc-statusline script in `setup()`:

```javascript
  // Install mc-statusline
  const statuslineSrc = join(__dirname, 'mc-statusline');
  const statuslineDest = join(MC_DIR, 'bin', 'mc-statusline');
  if (existsSync(statuslineSrc)) {
    copyFileSync(statuslineSrc, statuslineDest);
    try { execSync(`chmod +x "${statuslineDest}"`, { stdio: 'pipe' }); } catch {}
    console.log('  ✓ Installed mc-statusline');
  }
```

- [ ] **Step 5: Build and verify**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme MissionControl -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add MissionControl/MissionControl/RateLimitMonitor.swift MissionControl/cli/bin/mc-statusline MissionControl/MissionControl/AgentStore.swift MissionControl/cli/bin/cli.mjs
git commit -m "feat: statusLine rate limit tracking

mc-statusline script extracts rate_limits from Claude Code JSON.
RateLimitMonitor watches /tmp/mc-rate-limits.json via kqueue.
Installer configures statusLine in Claude Code settings."
```

---

## Task 9: Auto Hook Recovery (HookGuard)

**Files:**
- Create: `MissionControl/MissionControl/HookGuard.swift`
- Modify: `MissionControl/MissionControl/AgentStore.swift`

- [ ] **Step 1: Create HookGuard.swift**

```swift
import Foundation

@MainActor
class HookGuard {
    private var fileMonitors: [DispatchSourceFileSystemObject] = []
    private var expectedHooks: [String: [[String: Any]]] = [:]

    private let claudeSettingsPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").path
    }()

    private let bridgePath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mission-control/bin/mc-bridge").path
    }()

    func startGuarding() {
        // Record baseline hooks
        recordBaseline()
        // Watch settings files
        watchFile(at: claudeSettingsPath)
    }

    func stopGuarding() {
        for monitor in fileMonitors {
            monitor.cancel()
        }
        fileMonitors.removeAll()
    }

    private func recordBaseline() {
        guard let data = FileManager.default.contents(atPath: claudeSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: [[String: Any]]] else {
            return
        }

        // Filter to only our hooks
        for (event, entries) in hooks {
            let ours = entries.filter { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { hook in
                    (hook["command"] as? String)?.contains("mc-bridge") == true
                }
            }
            if !ours.isEmpty {
                expectedHooks[event] = ours
            }
        }
    }

    private func watchFile(at path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.checkAndRecover()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileMonitors.append(source)
    }

    private func checkAndRecover() {
        guard !expectedHooks.isEmpty else { return }
        guard let data = FileManager.default.contents(atPath: claudeSettingsPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        var hooks = json["hooks"] as? [String: [[String: Any]]] ?? [:]
        var needsWrite = false

        for (event, ourEntries) in expectedHooks {
            let existing = hooks[event] ?? []
            let hasOurs = existing.contains { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { hook in
                    (hook["command"] as? String)?.contains("mc-bridge") == true
                }
            }

            if !hasOurs {
                // Our hooks were removed — merge them back
                hooks[event] = existing + ourEntries
                needsWrite = true
                print("HookGuard: recovered \(event) hook")
            }
        }

        if needsWrite {
            json["hooks"] = hooks
            if let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try? newData.write(to: URL(fileURLWithPath: claudeSettingsPath))
            }
        }
    }
}
```

- [ ] **Step 2: Add HookGuard to AgentStore**

In `AgentStore.swift`, add:

```swift
    let hookGuard = HookGuard()
```

In `startWatching()`, add:

```swift
        hookGuard.startGuarding()
```

In `stopWatching()`, add:

```swift
        hookGuard.stopGuarding()
```

- [ ] **Step 3: Build and verify**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme MissionControl -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add MissionControl/MissionControl/HookGuard.swift MissionControl/MissionControl/AgentStore.swift
git commit -m "feat: auto hook recovery via kqueue file watching

HookGuard monitors ~/.claude/settings.json. If MissionControl hooks
are removed (e.g. by Claude Code update), merges them back while
preserving other tools' configuration."
```

---

## Task 10: Chiptune Sound Effects

**Files:**
- Create: `MissionControl/MissionControl/Audio/ChiptuneEngine.swift`
- Modify: `MissionControl/MissionControl/AgentStore.swift`

- [ ] **Step 1: Create Audio directory**

```bash
mkdir -p /Users/kochunlong/MissionControl/MissionControl/Audio
```

- [ ] **Step 2: Create ChiptuneEngine.swift**

```swift
import AVFoundation

@MainActor
class ChiptuneEngine {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let sampleRate: Double = 44100
    private let format: AVAudioFormat

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        setupEngine()
        observeAudioDeviceChanges()
    }

    private func setupEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            audioEngine = engine
            playerNode = player
        } catch {
            print("ChiptuneEngine: failed to start audio engine: \(error)")
        }
    }

    private func observeAudioDeviceChanges() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine, queue: .main
        ) { [weak self] _ in
            self?.audioEngine?.stop()
            self?.setupEngine()
        }
    }

    enum Waveform {
        case square, triangle
    }

    func playAlert() {
        // Rising: C5 → E5 → G5
        let notes: [(freq: Float, duration: Float)] = [
            (523.25, 0.08), (659.25, 0.08), (783.99, 0.12)
        ]
        play(notes: notes, waveform: .square, volume: 0.3)
    }

    func playApproved() {
        // Confirm: G5 → C6
        let notes: [(freq: Float, duration: Float)] = [
            (783.99, 0.06), (1046.5, 0.1)
        ]
        play(notes: notes, waveform: .triangle, volume: 0.25)
    }

    func playDenied() {
        // Falling: E5 → C4
        let notes: [(freq: Float, duration: Float)] = [
            (659.25, 0.08), (261.63, 0.12)
        ]
        play(notes: notes, waveform: .square, volume: 0.25)
    }

    func playSessionDone() {
        // Complete: C5 → E5 → G5 → C6
        let notes: [(freq: Float, duration: Float)] = [
            (523.25, 0.06), (659.25, 0.06), (783.99, 0.06), (1046.5, 0.15)
        ]
        play(notes: notes, waveform: .triangle, volume: 0.25)
    }

    private func play(notes: [(freq: Float, duration: Float)], waveform: Waveform, volume: Float) {
        guard let player = playerNode, let engine = audioEngine, engine.isRunning else { return }

        let totalDuration = notes.reduce(0) { $0 + $1.duration }
        let frameCount = AVAudioFrameCount(Double(totalDuration) * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return }

        var sampleIndex: AVAudioFrameCount = 0
        for note in notes {
            let noteSamples = AVAudioFrameCount(Double(note.duration) * sampleRate)
            for i in 0..<noteSamples {
                let t = Float(i) / Float(sampleRate)
                let phase = note.freq * t
                let sample: Float

                switch waveform {
                case .square:
                    sample = (phase.truncatingRemainder(dividingBy: 1.0) < 0.5) ? volume : -volume
                case .triangle:
                    let p = phase.truncatingRemainder(dividingBy: 1.0)
                    sample = volume * (p < 0.5 ? 4.0 * p - 1.0 : 3.0 - 4.0 * p)
                }

                // Apply envelope (fade in/out to avoid clicks)
                let fadeLen: AVAudioFrameCount = 100
                var envelope: Float = 1.0
                if i < fadeLen { envelope = Float(i) / Float(fadeLen) }
                if i > noteSamples - fadeLen { envelope = Float(noteSamples - i) / Float(fadeLen) }

                if sampleIndex < frameCount {
                    channelData[Int(sampleIndex)] = sample * envelope
                    sampleIndex += 1
                }
            }
        }

        player.scheduleBuffer(buffer, at: nil, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
```

- [ ] **Step 3: Replace NSSound with ChiptuneEngine in AgentStore**

In `AgentStore.swift`, add property:

```swift
    let chiptuneEngine = ChiptuneEngine()
```

In `triggerAlert(for:)`, replace:

```swift
        NSSound(named: "Ping")?.play()
```

With:

```swift
        chiptuneEngine.playAlert()
```

- [ ] **Step 4: Add sound effects to approve/deny actions**

In `respondPermission`, after the allow/deny logic:

```swift
        if allow {
            chiptuneEngine.playApproved()
        } else {
            chiptuneEngine.playDenied()
        }
```

In `handleStatusUpdate`, when status changes to `.done`:

```swift
            if newStatus == .done && oldStatus != .done {
                chiptuneEngine.playSessionDone()
            }
```

- [ ] **Step 5: Build and verify**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme MissionControl -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add MissionControl/MissionControl/Audio/ MissionControl/MissionControl/AgentStore.swift
git commit -m "feat: 8-bit chiptune sound effects

Real-time waveform synthesis (square + triangle) via AVAudioEngine.
Alert (rising), approved (confirm), denied (falling), done (fanfare).
Handles audio device switching. Replaces system Ping sound."
```

---

## Task 11: Integration Test — End-to-End Verification

**Files:**
- No new files

- [ ] **Step 1: Build both targets**

Run: `cd /Users/kochunlong/MissionControl && xcodegen generate && xcodebuild -scheme MissionControl -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

Run: `cd /Users/kochunlong/MissionControl && xcodebuild -scheme mc-bridge -configuration Release build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify bridge binary works**

Run: `echo '{"cwd":"/tmp/test","session_id":"test12345678"}' | /Users/kochunlong/MissionControl/MissionControl/Helpers/mc-bridge --source claude --event SessionStart`
Expected: exits cleanly (socket may not be running, that's OK)

- [ ] **Step 3: Verify launcher shim**

Run: `file /Users/kochunlong/MissionControl/cli/bin/mc-bridge`
Expected: shows it's a shell script

- [ ] **Step 4: Run the app and verify no crashes**

Run: `cd /Users/kochunlong/MissionControl && open build/Debug/MissionControl.app`
Expected: app launches, positions at notch/top-center, no crashes

- [ ] **Step 5: Verify hook config generation**

Run: `node /Users/kochunlong/MissionControl/cli/bin/cli.mjs setup claude-code 2>&1`
Expected: shows 12 hook events configured, bridge shim installed

- [ ] **Step 6: Final commit with any fixes**

If any fixes were needed during testing:

```bash
git add -A
git commit -m "fix: integration test fixes for Vibe Island parity upgrade"
```
