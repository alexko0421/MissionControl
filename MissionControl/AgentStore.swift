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
    }

    func stopWatching() {
        socketServer.stopListening()
        stopPolling()
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
            let target = agents[i].tmuxTarget
            let status = agents[i].status
            guard let target = target else { continue }

            Task.detached { [status] in
                let lines = TMuxBridge.capturePane(target: target)
                // Detect prompts for blocked agents
                let prompt: AgentQuestion? = (status == .blocked)
                    ? TMuxBridge.detectPrompt(target: target) : nil

                await MainActor.run { [weak self, lines, prompt] in
                    guard let self = self,
                          let idx = self.agents.firstIndex(where: { $0.tmuxTarget == target }) else { return }
                    if !lines.isEmpty {
                        self.agents[idx].terminalLines = lines
                    }
                    // Show detected prompt as question card
                    if let prompt = prompt, self.agents[idx].pendingQuestion == nil {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.agents[idx].pendingQuestion = prompt
                        }
                        self.triggerAlert(for: self.agents[idx])
                        self.autoSwitchTab()
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
            if agent.status == .idle && age > 7200 { return true }
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
                agents[idx].updatedAt = Date()
            }

            // Alert on status change to blocked/done
            if oldStatus != newStatus && (newStatus == .blocked || newStatus == .done) {
                triggerAlert(for: agents[idx])
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

        pendingClientFDs[requestId] = clientFD

        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingPermission = request
                agents[idx].status = .blocked
                agents[idx].updatedAt = Date()
            }
            triggerAlert(for: agents[idx])
            // Auto-switch to Approve tab
            autoSwitchTab()
        }
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
        activeAlert = AgentAlert(
            agentId: agent.id,
            agentName: agent.name,
            newStatus: agent.status,
            task: agent.task
        )
        NSSound(named: "Ping")?.play()
    }

    // MARK: - Permission Choice

    enum PermissionChoice {
        case yes            // Send "1" → Yes
        case yesDontAskAgain // Send "2" → Yes, don't ask again
        case no             // Send "3" → No

        var tmuxKey: String {
            switch self {
            case .yes: return "1"
            case .yesDontAskAgain: return "2"
            case .no: return "3"
            }
        }

        var isApproval: Bool {
            switch self {
            case .yes, .yesDontAskAgain: return true
            case .no: return false
            }
        }
    }

    // MARK: - Approve / Deny Actions

    func respondPermission(agentId: String, requestId: String, choice: PermissionChoice) {
        let decision = choice.isApproval ? "approve" : "deny"
        sendDecision(requestId: requestId, type: "permission_response", decision: decision)
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            if let target = agents[idx].tmuxTarget {
                let key = choice.tmuxKey
                Task.detached { TMuxBridge.sendKeys(target: target, command: key) }
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                agents[idx].pendingPermission = nil
                agents[idx].status = choice.isApproval ? .running : agents[idx].status
                agents[idx].updatedAt = Date()
            }
        }
        collapseIfNoPending()
    }

    func approvePlan(agentId: String, requestId: String) {
        sendDecision(requestId: requestId, type: "plan_response", decision: "approve")
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            if let target = agents[idx].tmuxTarget {
                Task.detached { TMuxBridge.sendKeys(target: target, command: "y") }
            }
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
            if let target = agents[idx].tmuxTarget {
                Task.detached { TMuxBridge.sendKeys(target: target, command: "n") }
            }
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

            let sendKey = option.sendKey
            if let target = agents[idx].tmuxTarget {
                // tmux session: send keys directly
                Task.detached {
                    let parts = sendKey.components(separatedBy: " ")
                    for part in parts {
                        TMuxBridge.sendKeys(target: target, command: part)
                        if parts.count > 1 { Thread.sleep(forTimeInterval: 0.1) }
                    }
                }
            } else {
                // Non-tmux: use AppleScript to type into Terminal after a short delay
                // (wait for Claude Code to show its prompt after hook exits)
                let appName = agents[idx].app ?? "Terminal"
                Task.detached {
                    Thread.sleep(forTimeInterval: 0.5)
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

    /// Type text into a terminal app using AppleScript keystroke injection
    nonisolated static func typeInTerminal(text: String, appName: String) {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        // Use System Events to type into the frontmost terminal process
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    func respondFreeText(agentId: String, text: String) {
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            let questionId = agents[idx].pendingQuestion?.id ?? ""
            sendDecision(requestId: questionId, type: "question_response", decision: "approve")
            if let target = agents[idx].tmuxTarget {
                Task.detached { TMuxBridge.sendKeys(target: target, command: text) }
            }
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

    private func sendDecision(requestId: String, type: String, decision: String) {
        guard let clientFD = pendingClientFDs.removeValue(forKey: requestId) else { return }
        let response = OutgoingMessage(type: type, requestId: requestId, decision: decision)
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
