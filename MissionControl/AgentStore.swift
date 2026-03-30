import Foundation
import SwiftUI
import Combine

// MARK: - AgentStore
// Central data store. Reads from ~/.mission-control/status.json
// and polls tmux for live terminal output.

@MainActor
class AgentStore: ObservableObject {
    @Published var agents: [Agent] = Agent.samples

    enum ViewState {
        case terminal
        case sessionList
        case summary(agentId: String)
    }

    @Published var viewState: ViewState = .terminal

    private let statusDir  = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent(".mission-control")
    private var statusFile: URL { statusDir.appendingPathComponent("status.json") }
    private var pollTimer: Timer?
    private var fileSource: DispatchSourceFileSystemObject?

    // MARK: - Lifecycle

    func startWatching() {
        createStatusDirIfNeeded()
        loadFromFile()
        startFileWatcher()
        startTmuxPolling()
    }

    func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
        fileSource?.cancel()
        fileSource = nil
    }

    // MARK: - Status File

    private func createStatusDirIfNeeded() {
        try? FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)
    }

    func loadFromFile() {
        guard FileManager.default.fileExists(atPath: statusFile.path) else { return }
        do {
            let data = try Data(contentsOf: statusFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([Agent].self, from: data)
            withAnimation(.easeInOut(duration: 0.2)) {
                self.agents = loaded
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

    // MARK: - tmux Polling
    // Polls every 5s to refresh terminal output for running agents

    private func startTmuxPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollTmuxAgents() }
        }
    }

    private func pollTmuxAgents() {
        let targets = agents.enumerated().compactMap { (i, a) -> (Int, String)? in
            guard a.status == .running, let target = a.tmuxTarget else { return nil }
            return (i, target)
        }
        guard !targets.isEmpty else { return }
        Task.detached {
            var results: [(Int, [TerminalLine])] = []
            for (i, target) in targets {
                let lines = TMuxBridge.capturePane(target: target, lastLines: 30)
                if !lines.isEmpty { results.append((i, lines)) }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (i, lines) in results where i < self.agents.count {
                    self.agents[i].terminalLines = lines
                    self.agents[i].updatedAt = Date()
                }
            }
        }
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
        }
    }
}
