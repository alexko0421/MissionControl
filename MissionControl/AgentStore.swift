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

    private let statusDir  = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent(".mission-control")
    private var statusFile: URL { statusDir.appendingPathComponent("status.json") }
    private var fileSource: DispatchSourceFileSystemObject?
    private var pollingTimer: Timer?
    private var lastFileData: Data?

    // MARK: - Lifecycle

    func startWatching() {
        createStatusDirIfNeeded()
        loadFromFile()
        startFileWatcher()
        startPolling()
    }

    func stopWatching() {
        fileSource?.cancel()
        fileSource = nil
        stopPolling()
    }

    private var scanCounter = 0

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Run external scanners every ~15 seconds (every 5th poll)
                self?.scanCounter += 1
                if self?.scanCounter ?? 0 >= 5 {
                    self?.scanCounter = 0
                    self?.runExternalScanners()
                }
                self?.loadFromFile()
                self?.pollTerminals()
            }
        }
    }

    private func runExternalScanners() {
        let scanners = [
            "mc-antigravity-scanner.py",
            "mc-codex-scanner.py",
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
            guard agents[i].status == .running,
                  let target = agents[i].tmuxTarget else { continue }
            Task.detached { [target] in
                let lines = TMuxBridge.capturePane(target: target)
                await MainActor.run { [weak self, lines] in
                    guard let self = self,
                          let idx = self.agents.firstIndex(where: { $0.tmuxTarget == target }) else { return }
                    if !lines.isEmpty {
                        self.agents[idx].terminalLines = lines
                        self.agents[idx].updatedAt = Date()
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

        agents.removeAll { agent in
            // Don't remove agent user is currently viewing
            if agent.id == viewingAgentId { return false }

            let age = now.timeIntervalSince(agent.updatedAt)
            switch agent.status {
            case .done:  return age > 3600      // 1 hour
            case .idle:  return age > 86400     // 24 hours
            default:     return false
            }
        }
    }

    // MARK: - Status File

    private func createStatusDirIfNeeded() {
        try? FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)
    }

    func loadFromFile() {
        guard FileManager.default.fileExists(atPath: statusFile.path) else { return }
        do {
            let data = try Data(contentsOf: statusFile)
            // Skip if file content hasn't changed
            if data == lastFileData { return }
            lastFileData = data
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([Agent].self, from: data)

            // Detect status changes before updating agents
            let now = Date()
            for agent in loaded {
                let oldStatus = previousStatuses[agent.id]
                let isNewBlockedOrDone = (agent.status == .blocked || agent.status == .done)
                let statusChanged = (oldStatus != nil && oldStatus != agent.status)
                let isFirstAppearanceBlocked = (oldStatus == nil && agent.status == .blocked)

                if (statusChanged || isFirstAppearanceBlocked) && isNewBlockedOrDone {
                    // Debounce check: skip if alerted within last 5 seconds
                    if let lastAlert = lastAlertTimes[agent.id],
                       now.timeIntervalSince(lastAlert) < 5 {
                        continue
                    }
                    // Focus mode: only alert for focused agent (or all if no focus)
                    if isFocusModeActive && agent.id != focusedAgentId {
                        continue
                    }
                    lastAlertTimes[agent.id] = now
                    activeAlert = AgentAlert(
                        agentId: agent.id,
                        agentName: agent.name,
                        newStatus: agent.status,
                        task: agent.task
                    )
                    // Play alert sound
                    NSSound(named: "Ping")?.play()
                }
            }

            // Update previous statuses
            previousStatuses = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.status) })

            withAnimation(.easeInOut(duration: 0.2)) {
                self.agents = loaded
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
        } catch {
            print("AgentStore: failed to load status.json — \(error)")
        }
    }

    func saveToFile() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(agents) else { return }
        try? data.write(to: statusFile)
    }

    // Watch the directory for changes (handles atomic writes and missing file)
    private func startFileWatcher() {
        let dirPath = statusDir.path
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in self?.loadFromFile() }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
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
            return a.updatedAt > b.updatedAt
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
