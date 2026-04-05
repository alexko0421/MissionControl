import Foundation
import SwiftUI
import Combine
import AppKit

// MARK: - AgentStore
// Central data store. Reads from ~/.mission-control/status.json
// and polls tmux for live terminal output.

@MainActor
class AgentStore: ObservableObject {
    @Published var agents: [Agent] = []

    enum ViewState {
        case terminal
        case sessionList
        case summary(agentId: String)
        case settings
    }

    @Published var viewState: ViewState = .terminal

    // Bottom tab mode
    enum TabMode: String, CaseIterable {
        case monitor, approve, ask, jump
    }
    @Published var activeTab: TabMode = .monitor

    // Alert state — drives pill flash + sound
    @Published var activeAlert: AgentAlert? = nil

    struct AgentAlert: Equatable {
        let agentId: String
        let agentName: String
        let newStatus: AgentStatus
        let task: String
    }

    // Track previous agent statuses for diff
    private var previousStatuses: [String: AgentStatus] = [:]

    // Debounce: don't re-alert same agent within 5 seconds
    private var lastAlertTimes: [String: Date] = [:]

    // Focus Mode — lock onto one agent, silence other alerts
    @AppStorage("focusedAgentId") var focusedAgentId: String = ""

    var isFocusModeActive: Bool { !focusedAgentId.isEmpty }

    var focusedAgent: Agent? {
        guard isFocusModeActive else { return nil }
        return agents.first { $0.id == focusedAgentId }
    }

    let socketServer = MCSocketServer()
    let rateLimitMonitor = RateLimitMonitor()
    let hookGuard = HookGuard()
    // System sounds for different events
    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
    private var pendingClientFDs: [String: Int32] = [:]  // requestId → clientFD

    private let statusDir  = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent(".mission-control")
    private var pollingTimer: Timer?

    // MARK: - Lifecycle

    func startWatching() {
        createStatusDirIfNeeded()
        migrateFromStatusFile()
        setupSocketServer()
        startPolling()
        rateLimitMonitor.startMonitoring()
        hookGuard.startGuarding()
    }

    func stopWatching() {
        socketServer.stopListening()
        stopPolling()
        rateLimitMonitor.stopMonitoring()
        hookGuard.stopGuarding()
    }

    private func setupSocketServer() {
        socketServer.onStatusUpdate = { [weak self] msg in
            self?.handleStatusUpdate(msg)
        }
        socketServer.onPermissionRequest = { [weak self] msg, clientFD in
            self?.handlePermissionRequest(msg, clientFD: clientFD)
        }
        socketServer.onPlanReview = { [weak self] msg, clientFD in
            self?.handlePlanReview(msg, clientFD: clientFD)
        }
        socketServer.onQuestion = { [weak self] msg, clientFD in
            self?.handleQuestion(msg, clientFD: clientFD)
        }
        socketServer.onQuestionResolved = { [weak self] msg in
            guard let self = self, let agentId = msg.agentId else { return }
            if let idx = self.agents.firstIndex(where: { $0.id == agentId }) {
                self.agents[idx].pendingPermission = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.agents[idx].pendingQuestion = nil
                    if self.agents[idx].status == .blocked {
                        self.agents[idx].status = .running
                    }
                    self.agents[idx].updatedAt = Date()
                }
                self.collapseIfNoPending()
            }
        }
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
        socketServer.startListening()
    }

    private var scanCounter = 0

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanCounter += 1
                if self?.scanCounter ?? 0 >= 2 {
                    self?.scanCounter = 0
                    self?.runExternalScanners()
                }
                self?.pollTerminals()
            }
        }
    }

    private func runExternalScanners() {
        let scanners = [
            "mc-session-checker.py",
            "mc-cleanup.py",
        ]
        let scriptsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/MissionControl/scripts")

        for scanner in scanners {
            let scriptPath = scriptsDir.appendingPathComponent(scanner).path
            guard FileManager.default.fileExists(atPath: scriptPath) else { continue }
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = [scriptPath]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func pollTerminals() {
        for i in agents.indices {
            guard let target = agents[i].tmuxTarget else { continue }

            Task.detached {
                let lines = TMuxBridge.capturePane(target: target)

                await MainActor.run { [weak self, lines] in
                    guard let self = self,
                          let idx = self.agents.firstIndex(where: { $0.tmuxTarget == target }) else { return }
                    if !lines.isEmpty {
                        self.agents[idx].terminalLines = lines
                    }
                    // Clear question if agent is no longer blocked
                    if self.agents[idx].status != .blocked && self.agents[idx].pendingQuestion != nil {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.agents[idx].pendingQuestion = nil
                        }
                    }
                }
            }
        }
    }

    private func cleanupStaleAgents() {
        let now = Date()
        let viewingAgentId: String? = {
            if case .summary(let id) = viewState { return id }
            return nil
        }()

        // Auto-downgrade stale statuses
        for i in agents.indices {
            let age = now.timeIntervalSince(agents[i].updatedAt)
            // done > 10 minutes → idle
            if agents[i].status == .done && age > 600 {
                agents[i].status = .idle
            }
            // running/blocked > 1 hour → idle
            if (agents[i].status == .running || agents[i].status == .blocked) && age > 3600 {
                agents[i].status = .idle
            }
        }

        agents.removeAll { agent in
            if agent.id == viewingAgentId { return false }
            let age = now.timeIntervalSince(agent.updatedAt)
            // idle > 2 hours → remove
            if agent.status == .idle && age > 1800 { return true }
            return false
        }

        // Agents are now in-memory only, persisted by socket updates
    }

    // MARK: - Status File

    private func createStatusDirIfNeeded() {
        try? FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)
    }

    private func migrateFromStatusFile() {
        let statusFile = statusDir.appendingPathComponent("status.json")
        guard FileManager.default.fileExists(atPath: statusFile.path) else { return }
        do {
            let data = try Data(contentsOf: statusFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([Agent].self, from: data)
            self.agents = loaded
            previousStatuses = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.status) })
        } catch {
            print("AgentStore: migration from status.json failed — \(error)")
        }
    }

    // MARK: - New Hook Event Handlers

    private func handleSessionStart(_ msg: IncomingMessage) {
        guard let agentId = msg.agentId else { return }
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

    // MARK: - Socket Message Handlers

    private func handleStatusUpdate(_ msg: IncomingMessage) {
        guard let agentId = msg.agentId else { return }
        let newStatus = AgentStatus(rawValue: msg.status ?? "running") ?? .running

        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            let oldStatus = agents[idx].status

            withAnimation(.easeInOut(duration: 0.2)) {
                if let name = msg.name { agents[idx].name = name }
                agents[idx].status = newStatus
                if let task = msg.task { agents[idx].task = task }
                if let summary = msg.summary { agents[idx].summary = summary }
                if let nextAction = msg.nextAction { agents[idx].nextAction = nextAction }
                if let worktree = msg.worktree { agents[idx].worktree = worktree }
                if let app = msg.app { agents[idx].app = app }
                if let agentType = msg.agentType { agents[idx].agentType = agentType }
                if let tmuxSession = msg.tmuxSession { agents[idx].tmuxSession = tmuxSession }
                if let tmuxWindow = msg.tmuxWindow { agents[idx].tmuxWindow = tmuxWindow }
                if let tmuxPane = msg.tmuxPane { agents[idx].tmuxPane = tmuxPane }
                if let env = msg.terminalEnv { agents[idx].terminalEnv = env }
                if let tty = msg.tty { agents[idx].tty = tty }
                if let parentId = msg.subagentParentId { agents[idx].subagentParentId = parentId }
                agents[idx].updatedAt = Date()
            }

            // Alert on status change to blocked/done
            if oldStatus != newStatus && (newStatus == .blocked || newStatus == .done) {
                triggerAlert(for: agents[idx])
            }
            if newStatus == .done && oldStatus != .done {
                playSound("Glass")
            }
        } else {
            // New agent
            var agent = Agent(
                id: agentId,
                name: msg.name ?? agentId,
                status: newStatus,
                task: msg.task ?? "",
                summary: msg.summary ?? "",
                terminalLines: [],
                nextAction: msg.nextAction ?? "",
                updatedAt: Date(),
                worktree: msg.worktree,
                app: msg.app,
                tmuxSession: msg.tmuxSession,
                tmuxWindow: msg.tmuxWindow,
                tmuxPane: msg.tmuxPane,
                agentType: msg.agentType
            )
            agent.terminalEnv = msg.terminalEnv
            agent.tty = msg.tty
            agent.subagentParentId = msg.subagentParentId

            withAnimation(.easeInOut(duration: 0.2)) {
                agents.append(agent)
            }
            previousStatuses[agentId] = newStatus

            if newStatus == .blocked {
                triggerAlert(for: agent)
            }
        }

        cleanupStaleAgents()

        // Auto-exit focus if focused agent is done or gone
        if isFocusModeActive {
            if let focused = agents.first(where: { $0.id == focusedAgentId }) {
                if focused.status == .done {
                    stopFocus()
                }
            } else {
                stopFocus()
            }
        }
    }

    private func handlePermissionRequest(_ msg: IncomingMessage, clientFD: Int32) {
        guard let agentId = msg.agentId,
              let requestId = msg.requestId,
              let tool = msg.tool else { return }

        let request = PermissionRequest(
            id: requestId,
            tool: tool,
            toolInput: msg.toolInput ?? [:],
            receivedAt: Date()
        )

        // Clean up old permission request for this agent (if any)
        if let idx = agents.firstIndex(where: { $0.id == agentId }),
           let oldRequestId = agents[idx].pendingPermission?.id {
            // Close old socket FD — the old worker is stale
            if let oldFD = pendingClientFDs.removeValue(forKey: oldRequestId) {
                socketServer.pendingResponseFDs.remove(oldFD)
                close(oldFD)
            }
        }

        // Store clientFD so respondPermission can send response back through socket
        pendingClientFDs[requestId] = clientFD

        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            if let session = msg.tmuxSession {
                agents[idx].tmuxSession = session
                agents[idx].tmuxWindow = msg.tmuxWindow
                agents[idx].tmuxPane = msg.tmuxPane
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingPermission = request
                agents[idx].status = .blocked
                agents[idx].updatedAt = Date()
            }
            triggerAlert(for: agents[idx])
            autoSwitchTab()
        } else {
            var agent = Agent(
                id: agentId,
                name: msg.name ?? agentId,
                status: .blocked,
                task: "\(tool) approval",
                summary: "",
                terminalLines: [],
                nextAction: "",
                updatedAt: Date(),
                tmuxSession: msg.tmuxSession,
                tmuxWindow: msg.tmuxWindow,
                tmuxPane: msg.tmuxPane
            )
            agent.pendingPermission = request
            withAnimation(.easeInOut(duration: 0.2)) {
                agents.append(agent)
            }
            triggerAlert(for: agent)
            autoSwitchTab()
        }
    }

    func respondPermission(agentId: String, allow: Bool) {
        guard let idx = agents.firstIndex(where: { $0.id == agentId }) else { return }

        // Send response back through socket (for any waiting hook process)
        if let requestId = agents[idx].pendingPermission?.id {
            let decision = allow ? "approve" : "deny"
            sendDecision(requestId: requestId, type: "permission_response", decision: decision)
        }

        // Send keystroke to terminal to answer the native prompt
        let tmuxTarget = agents[idx].tmuxTarget
        let tty = agents[idx].tty
        let appName = agents[idx].app ?? "Terminal"
        // Debug log to file
        let debugLine = "[MC-PERM] agentId=\(agentId) tmux=\(tmuxTarget ?? "nil") tty=\(tty ?? "nil") app=\(appName) allow=\(allow)\n"
        if let data = debugLine.data(using: .utf8) {
            let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mission-control/mc-perm.log")
            if let fh = try? FileHandle(forWritingTo: logPath) {
                fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
            } else {
                FileManager.default.createFile(atPath: logPath.path, contents: data)
            }
        }

        Task.detached {
            Thread.sleep(forTimeInterval: 0.3)
            if let target = tmuxTarget {
                if allow {
                    TMuxBridge.sendKeys(target: target, command: "Enter")
                } else {
                    TMuxBridge.sendKeys(target: target, command: "Escape")
                }
            } else if let tty = tty {
                AgentStore.writeToTTY(tty: tty, text: allow ? "\r" : "\u{1b}")
            } else {
                // AppleScript fallback — bring terminal to front and press Enter/Escape
                let keyCode = allow ? 36 : 53  // 36=Return, 53=Escape
                let script = """
                tell application "System Events"
                    tell process "\(appName)"
                        set frontmost to true
                        delay 0.3
                        key code \(keyCode)
                    end tell
                end tell
                """
                var errorDict: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                appleScript?.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    print("[MC] AppleScript error: \(error)")
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            agents[idx].pendingPermission = nil
            agents[idx].status = allow ? .running : agents[idx].status
            agents[idx].updatedAt = Date()
        }
        if allow {
            playSound("Hero")
        } else {
            playSound("Basso")
        }
        collapseIfNoPending()
    }

    /// Write directly to a TTY device (no tmux needed, no focus needed)
    nonisolated static func writeToTTY(tty: String, text: String) {
        guard let fh = FileHandle(forWritingAtPath: tty) else {
            print("[MC] writeToTTY failed: cannot open \(tty)")
            return
        }
        fh.write(Data(text.utf8))
        fh.closeFile()
    }

    private func handlePlanReview(_ msg: IncomingMessage, clientFD: Int32) {
        guard let agentId = msg.agentId,
              let requestId = msg.requestId,
              let markdown = msg.markdown else { return }

        let review = PlanReview(
            id: requestId,
            markdown: markdown,
            receivedAt: Date()
        )

        pendingClientFDs[requestId] = clientFD

        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingPlan = review
                agents[idx].status = .blocked
                agents[idx].updatedAt = Date()
            }
            triggerAlert(for: agents[idx])
            autoSwitchTab()
        }
    }

    private func handleQuestion(_ msg: IncomingMessage, clientFD: Int32) {
        guard let agentId = msg.agentId,
              let requestId = msg.requestId,
              let questionText = msg.question else { return }

        pendingClientFDs[requestId] = clientFD

        // Build options from message
        var questionOptions: [AgentQuestion.QuestionOption] = []
        if let opts = msg.options {
            for (i, opt) in opts.enumerated() {
                questionOptions.append(.init(
                    id: Int(opt["id"] ?? "\(i+1)") ?? (i+1),
                    label: opt["label"] ?? "Option \(i+1)",
                    sendKey: opt["sendKey"] ?? "\(i+1)",
                    isHighlighted: i == 0
                ))
            }
        }

        let agentQuestion = AgentQuestion(
            id: requestId,
            question: questionText,
            options: questionOptions,
            promptType: questionOptions.isEmpty ? .freeInput : .numbered,
            detectedAt: Date()
        )

        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            // Store tmux info from question message if available
            print("[MC-DEBUG] handleQuestion: agentId=\(agentId), tmuxSession=\(msg.tmuxSession ?? "nil"), tmuxWindow=\(msg.tmuxWindow ?? -1), tmuxPane=\(msg.tmuxPane ?? -1)")
            if let session = msg.tmuxSession {
                agents[idx].tmuxSession = session
                agents[idx].tmuxWindow = msg.tmuxWindow
                agents[idx].tmuxPane = msg.tmuxPane
                print("[MC-DEBUG] Stored tmux info: \(session):\(msg.tmuxWindow ?? 0).\(msg.tmuxPane ?? 0)")
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingQuestion = agentQuestion
                agents[idx].status = .blocked
                agents[idx].updatedAt = Date()
            }
            triggerAlert(for: agents[idx])
            autoSwitchTab()
        }
    }

    private func triggerAlert(for agent: Agent) {
        let now = Date()
        // Debounce: skip if alerted within last 30 seconds for the same agent
        if let lastAlert = lastAlertTimes[agent.id],
           now.timeIntervalSince(lastAlert) < 30 {
            return
        }
        // Focus mode: only alert for focused agent (or all if no focus)
        if isFocusModeActive && agent.id != focusedAgentId {
            return
        }
        lastAlertTimes[agent.id] = now
        let alert = AgentAlert(
            agentId: agent.id,
            agentName: agent.name,
            newStatus: agent.status,
            task: agent.task
        )
        activeAlert = alert
        playSound("Glass")
    }

    // MARK: - Approve / Deny Actions

    func approvePlan(agentId: String, requestId: String) {
        sendDecision(requestId: requestId, type: "plan_response", decision: "approve")
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingPlan = nil
                agents[idx].status = .running
                agents[idx].updatedAt = Date()
            }
        }
        collapseIfNoPending()
    }

    func denyPlan(agentId: String, requestId: String) {
        sendDecision(requestId: requestId, type: "plan_response", decision: "deny")
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingPlan = nil
                agents[idx].updatedAt = Date()
            }
        }
        collapseIfNoPending()
    }

    func respondQuestion(agentId: String, option: AgentQuestion.QuestionOption) {
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            let questionId = agents[idx].pendingQuestion?.id ?? ""
            let decision = option.sendKey == "3" || option.sendKey == "n" ? "deny" : "approve"
            sendDecision(requestId: questionId, type: "question_response", decision: decision)

            // Send keystroke to terminal
            let sendKey = option.sendKey
            let tmuxTarget = agents[idx].tmuxTarget
            let tty = agents[idx].tty
            let appName = agents[idx].app ?? "Terminal"

            Task.detached {
                Thread.sleep(forTimeInterval: 0.3)
                if let target = tmuxTarget {
                    let parts = sendKey.components(separatedBy: " ")
                    for part in parts {
                        TMuxBridge.sendKeys(target: target, command: part)
                        if parts.count > 1 { Thread.sleep(forTimeInterval: 0.1) }
                    }
                } else if let tty = tty {
                    Self.writeToTTY(tty: tty, text: sendKey + "\n")
                } else {
                    Self.typeInTerminal(text: sendKey, appName: appName)
                }
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingQuestion = nil
                agents[idx].status = .running
                agents[idx].updatedAt = Date()
            }
        }
        collapseIfNoPending()
    }

    /// Find any active tmux pane as fallback when agent doesn't have tmux info
    nonisolated static func findActiveTmuxTarget() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/tmux")
        process.arguments = ["list-panes", "-aF", "#{session_name}:#{window_index}.#{pane_index} #{pane_active}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Find the first active pane
                for line in output.components(separatedBy: "\n") {
                    let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                    if parts.count >= 2 && parts[1] == "1" {
                        print("[MC-DEBUG] Found active tmux pane: \(parts[0])")
                        return parts[0]
                    }
                }
            }
        } catch {
            print("[MC-DEBUG] tmux list-panes failed: \(error)")
        }
        return nil
    }

    /// Type text into a terminal app using NSAppleScript (runs in-process, uses MissionControl's accessibility permissions)
    nonisolated static func typeInTerminal(text: String, appName: String) {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            tell process "\(appName)"
                set frontmost to true
                delay 0.3
                keystroke "\(escaped)"
                keystroke return
            end tell
        end tell
        """
        var errorDict: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(&errorDict)
        if let error = errorDict {
            print("AppleScript error for \(appName): \(error)")
        }
    }

    func respondFreeText(agentId: String, text: String) {
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            let questionId = agents[idx].pendingQuestion?.id ?? ""
            sendDecision(requestId: questionId, type: "question_response", decision: "approve", answer: text)
            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingQuestion = nil
                agents[idx].status = .running
                agents[idx].updatedAt = Date()
            }
        }
        collapseIfNoPending()
    }

    // MARK: - Tab Helpers

    /// Agents needing approval (permission or plan)
    var approveAgents: [Agent] {
        agents.filter { $0.pendingPermission != nil || $0.pendingPlan != nil }
    }

    /// Agents with pending questions
    var askAgents: [Agent] {
        agents.filter { $0.pendingQuestion != nil }
    }

    /// Switch to appropriate tab and auto-expand
    func autoSwitchTab() {
        if !approveAgents.isEmpty {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeTab = .approve
            }
            showSessionList()
        } else if !askAgents.isEmpty {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeTab = .ask
            }
            showSessionList()
        }
    }

    /// Auto-collapse or switch back to monitor when no more pending items
    private func collapseIfNoPending() {
        let hasPending = agents.contains {
            $0.pendingPermission != nil || $0.pendingPlan != nil || $0.pendingQuestion != nil
        }
        if !hasPending {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeTab = .monitor
            }
            showTerminal()
        }
    }

    private func sendDecision(requestId: String, type: String, decision: String, answer: String? = nil, reason: String? = nil) {
        guard let clientFD = pendingClientFDs.removeValue(forKey: requestId) else { return }
        var response = OutgoingMessage(type: type, requestId: requestId, decision: decision)
        response.answer = answer
        response.reason = reason
        socketServer.sendResponse(to: clientFD, message: response)
    }

    // MARK: - Actions

    func sendCommand(_ text: String, to agent: Agent) {
        guard let target = agent.tmuxTarget else {
            appendUserMessage(text, agentId: agent.id)
            return
        }
        appendUserMessage(text, agentId: agent.id)
        Task.detached {
            TMuxBridge.sendKeys(target: target, command: text)
        }
    }

    private func appendUserMessage(_ text: String, agentId: String) {
        guard let i = agents.firstIndex(where: { $0.id == agentId }) else { return }
        let line = TerminalLine(text: "▶ \(text)", type: .success)
        agents[i].terminalLines.append(line)
        agents[i].updatedAt = Date()
    }

    // MARK: - Computed

    var runningCount: Int  { agents.filter { $0.status == .running }.count }
    var blockedCount: Int  { agents.filter { $0.status == .blocked }.count }
    var doneCount: Int     { agents.filter { $0.status == .done    }.count }

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

    var sortedAgents: [Agent] {
        agents.sorted { a, b in
            let order: [AgentStatus] = [.blocked, .running, .done, .idle]
            let ai = order.firstIndex(of: a.status) ?? 99
            let bi = order.firstIndex(of: b.status) ?? 99
            if ai != bi { return ai < bi }
            // Same status: sort by name for stability (no jumping)
            return a.name < b.name
        }
    }

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

    var isSessionListOpen: Bool {
        if case .sessionList = viewState { return true }
        return false
    }

    var summaryAgent: Agent? {
        if case .summary(let id) = viewState {
            return agents.first { $0.id == id }
        }
        return nil
    }

    var viewStateKey: String {
        switch viewState {
        case .terminal: return "terminal"
        case .sessionList: return "sessionList"
        case .summary(let id): return "summary-\(id)"
        case .settings: return "settings"
        }
    }

    func jumpToAgent(_ agent: Agent) {
        Task {
            await JumpEngine.jump(to: agent)
        }
    }

    func dismissAlert() {
        withAnimation(.easeOut(duration: 0.3)) {
            activeAlert = nil
        }
    }

    func startFocus(agentId: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            focusedAgentId = agentId
        }
    }

    func stopFocus() {
        withAnimation(.easeInOut(duration: 0.2)) {
            focusedAgentId = ""
        }
    }
}
