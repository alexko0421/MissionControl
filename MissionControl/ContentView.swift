import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(spacing: 16) {
            // The capsule widget always on top visually
            CapsuleBar()
                .zIndex(2)

            // Expanded content (session list or summary) container
            // We use ZStack or just VStack to manage the emerging views so they render below CapsuleBar
            VStack(spacing: 0) {
                if case .sessionList = store.viewState {
                    SessionListPanel()
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: -20))
                                    .combined(with: .scale(scale: 0.95, anchor: .top)),
                                removal: .opacity
                                    .combined(with: .offset(y: -15))
                                    .combined(with: .scale(scale: 0.95, anchor: .top))
                            )
                        )
                }

                if case .summary(let agentId) = store.viewState {
                    if let agent = store.agents.first(where: { $0.id == agentId }) {
                        SummaryPanel(agent: agent)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity
                                        .combined(with: .offset(y: -20))
                                        .combined(with: .scale(scale: 0.95, anchor: .top)),
                                    removal: .opacity
                                        .combined(with: .offset(y: -15))
                                        .combined(with: .scale(scale: 0.95, anchor: .top))
                                )
                            )
                    }
                }
                
                if case .settings = store.viewState {
                    SettingsInlinePanel()
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .offset(y: -20))
                                    .combined(with: .scale(scale: 0.95, anchor: .top)),
                                removal: .opacity
                                    .combined(with: .offset(y: -15))
                                    .combined(with: .scale(scale: 0.95, anchor: .top))
                            )
                        )
                }
            }
            .zIndex(1)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: store.viewStateKey)
        .fixedSize()
    }
}

// MARK: - Capsule Bar (always visible)

struct CapsuleBar: View {
    @EnvironmentObject var store: AgentStore
    @State private var isMenuHovered = false
    @AppStorage("appLanguage") private var appLanguage = "Auto"
    private var isEn: Bool { appLanguage == "En" }

    var body: some View {
        HStack(spacing: 8) {
            // Left circular button
            Button(action: { store.toggleSessionList() }) {
                Image(systemName: store.isSessionListOpen ? "xmark" : "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(isMenuHovered ? 1.0 : 0.8))
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial)
                    .background(Color.white.opacity(isMenuHovered ? 0.1 : 0.05))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.white.opacity(isMenuHovered ? 0.3 : 0.2), lineWidth: 0.5)
                    )
                    .scaleEffect(isMenuHovered ? 1.04 : 1.0)
                    .shadow(color: .black.opacity(isMenuHovered ? 0.15 : 0.1), radius: isMenuHovered ? 6 : 4, y: 2)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                    isMenuHovered = hovering
                }
            }

            // Right input-like capsule
            HStack(spacing: 8) {
                if let agent = store.priorityAgent {
                    // Inner pill for agent status/name
                    HStack(spacing: 4) {
                        StatusDot(status: agent.status)
                        Text(agent.name.count > 10 ? String(agent.name.prefix(10)) + "..." : agent.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                        if store.isFocusModeActive && store.focusedAgentId == agent.id {
                            Image(systemName: "scope")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )

                    // Task text — or "safe to focus" signal when no agent needs you
                    SafeToFocusOrTask(
                        task: agent.task,
                        blockedCount: store.blockedCount,
                        hasAgents: !store.agents.isEmpty
                    )
                    
                    Spacer(minLength: 0)
                } else {
                    // Empty state
                    HStack(spacing: 5) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(isEn ? "Idle" : "待命中")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )

                    Text(isEn ? "Waiting for task..." : "等待任务中...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.leading, 4)
                        
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: 40)
            .background(.thinMaterial)
            .background(Color.black.opacity(0.2))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .alertPulse(isActive: store.activeAlert != nil)
            .animation(.spring(response: 0.55, dampingFraction: 0.9), value: store.priorityAgent?.id)
            .contentShape(Capsule())
            .onTapGesture {
                if let agent = store.priorityAgent {
                    jumpToPriorityAgent(agent: agent)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .onChange(of: store.activeAlert) { newAlert in
            if newAlert != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    store.dismissAlert()
                }
            }
        }
        .onTapGesture {
            if store.isFocusModeActive {
                store.stopFocus()
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func jumpToPriorityAgent(agent: Agent) {
        let appName = agent.app ?? "Terminal"
        let dirName = ((agent.worktree ?? "") as NSString).lastPathComponent
        let agentName = agent.name

        Task.detached {
            if appName == "Terminal" {
                let script = """
                tell application "Terminal"
                    repeat with w in windows
                        set winName to name of w
                        if winName contains "\(dirName)" or winName contains "\(agentName)" then
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                    activate
                end tell
                """
                SummaryPanel.runAppleScript(script)
            } else {
                await MainActor.run {
                    let workspace = NSWorkspace.shared
                    if let app = workspace.runningApplications.first(where: {
                        $0.localizedName == appName || $0.bundleIdentifier?.localizedCaseInsensitiveContains(appName.lowercased()) == true
                    }) {
                        app.activate()
                    }
                }
            }
        }
    }
}

// MARK: - Safe to Focus Signal

struct SafeToFocusOrTask: View {
    let task: String
    let blockedCount: Int
    let hasAgents: Bool
    @AppStorage("appLanguage") private var appLanguage = "Auto"

    private let safeColor = Color(red: 0.365, green: 0.792, blue: 0.647)
    private var safeText: String { appLanguage == "En" ? "All clear" : "安心工作" }

    var body: some View {
        Group {
            if blockedCount == 0 && hasAgents {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(safeColor)
                    Text(safeText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(safeColor.opacity(0.9))
                }
            } else {
                Text(task)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: blockedCount)
    }
}

// MARK: - Session List Panel (dropdown)

struct SessionListPanel: View {
    @EnvironmentObject var store: AgentStore
    @AppStorage("appLanguage") private var appLanguage = "Auto"

    private var isEn: Bool { appLanguage == "En" }

    var body: some View {
        VStack(spacing: 4) {
            if store.sortedAgents.isEmpty {
                // Empty state
                VStack(spacing: 10) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.25))
                    Text(isEn ? "No active sessions" : "暂无活跃任务")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(isEn ? "Start an AI coding session to see it here" : "启动 AI 编程任务后将自动显示")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.25))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            } else {
                let groupedAgents = Dictionary(grouping: store.sortedAgents, by: { $0.displayApp })
                let priorityOrder: [AgentStatus] = [.blocked, .running, .done, .idle]
                let sortedKeys = groupedAgents.keys.sorted { a, b in
                    let bestA = groupedAgents[a]!.compactMap { ag in priorityOrder.firstIndex(of: ag.status) }.min() ?? 99
                    let bestB = groupedAgents[b]!.compactMap { ag in priorityOrder.firstIndex(of: ag.status) }.min() ?? 99
                    if bestA != bestB { return bestA < bestB }
                    return a < b
                }

                ForEach(sortedKeys, id: \.self) { appName in
                    if let agents = groupedAgents[appName] {
                        HStack(spacing: 6) {
                            Image(systemName: agents[0].appIcon)
                                .font(.system(size: 10))
                            Text(appName.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1)
                            Spacer()
                        }
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 2)

                        ForEach(agents) { agent in
                            SessionRow(agent: agent)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
                                        store.showSummary(for: agent.id)
                                    }
                                }
                        }
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 4)
            
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
                        store.viewState = .settings
                    }
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(4)
                        .background(Color.white.opacity(0.001))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    NSCursor.pointingHand.set()
                }
            }
            .padding(.trailing, 4)
        }
        .padding(10)
        .frame(width: 360)
        .background(.thinMaterial)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.bottom, 12)
        .environment(\.colorScheme, .dark)
        .onAppear { Agent.displayLanguage = appLanguage }
        .onChange(of: appLanguage) { Agent.displayLanguage = $0 }
    }
}

struct SessionRow: View {
    let agent: Agent
    @EnvironmentObject var store: AgentStore
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            // === Existing HStack row content ===
            HStack(spacing: 8) {
                StatusDot(status: agent.status)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(isHovered ? 1.0 : 0.95))
                        .lineLimit(1)

                    Text(agent.task)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(isHovered ? 0.75 : 0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(agent.status.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(agent.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minWidth: 44)
                    .background(agent.status.color.opacity(0.15), in: Capsule())

                if store.isFocusModeActive && store.focusedAgentId == agent.id {
                    Image(systemName: "scope")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.365, green: 0.792, blue: 0.647))
                }

                Text(agent.timeAgo)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 54, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0))
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: isHovered)
            .onHover { isHovered = $0 }
            .onLongPressGesture(minimumDuration: 0.5) {
                store.startFocus(agentId: agent.id)
            }
            .contentShape(Rectangle())

            // Permission card (inline)
            if let permission = agent.pendingPermission {
                PermissionCardView(agent: agent, permission: permission)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: UnitPoint.top)))
            }

            // Plan review card (inline) — TODO: Task 5
            // if let plan = agent.pendingPlan {
            //     PlanReviewView(agent: agent, plan: plan)
            //         .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            // }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: agent.pendingPermission?.id)
    }
}

// MARK: - Summary Panel (expanded detail)

struct SummaryPanel: View {
    let agent: Agent
    @EnvironmentObject var store: AgentStore
    @State private var isHoveringClose = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                StatusDot(status: agent.status)
                    
                Text(agent.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: { store.showTerminal() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(isHoveringClose ? 0.9 : 0.6))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(isHoveringClose ? 0.15 : 0.1), in: Circle())
                        .scaleEffect(isHoveringClose ? 1.05 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        isHoveringClose = hovering
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                // Task
                InfoBlock(label: "TASK", text: agent.task)

                // Summary
                InfoBlock(label: "SUMMARY", text: agent.summary)
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
            )

            // Next action — tap to jump to tmux session
            Button(action: { jumpToSession(agent: agent) }) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: agent.tmuxSession != nil ? "arrow.right.circle.fill" : "arrow.right.circle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 1)

                    Text(agent.nextAction)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 360)
        .background(.thinMaterial)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.bottom, 12)
        .environment(\.colorScheme, .dark)
    }

    private func jumpToSession(agent: Agent) {
        // Try tmux first
        if let target = agent.tmuxTarget, agent.tmuxSession != nil {
            Task.detached {
                let selectCmd = "tmux select-window -t \"\(target)\" 2>/dev/null; tmux select-pane -t \"\(target)\" 2>/dev/null"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", selectCmd]
                try? process.run()
                process.waitUntilExit()

                Self.runAppleScript("tell application \"Terminal\" to activate")
            }
            return
        }

        // Find the correct window and activate it
        let appName = agent.app ?? "Terminal"
        let agentName = agent.name
        let worktree = agent.worktree ?? ""
        let dirName = (worktree as NSString).lastPathComponent

        Task.detached {
            if appName == "Terminal" {
                // Search Terminal windows by title for matching agent
                let script = """
                tell application "Terminal"
                    repeat with w in windows
                        set winName to name of w
                        if winName contains "\(dirName)" or winName contains "\(agentName)" then
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                    activate
                end tell
                return false
                """
                Self.runAppleScript(script)
            } else if appName == "Conductor" {
                // Conductor: try to find matching window, fall back to activate
                let script = """
                tell application "System Events"
                    if exists process "conductor" then
                        tell process "conductor"
                            repeat with w in windows
                                if name of w contains "\(dirName)" or name of w contains "\(agentName)" then
                                    perform action "AXRaise" of w
                                    set frontmost to true
                                    return true
                                end if
                            end repeat
                            set frontmost to true
                        end tell
                    end if
                end tell
                """
                Self.runAppleScript(script)
                // Also activate via NSWorkspace as backup
                await MainActor.run {
                    if let app = NSWorkspace.shared.runningApplications.first(where: {
                        $0.localizedName == appName || $0.bundleIdentifier?.localizedCaseInsensitiveContains(appName.lowercased()) == true
                    }) {
                        app.activate()
                    }
                }
            } else {
                await MainActor.run {
                    let workspace = NSWorkspace.shared
                    if let app = workspace.runningApplications.first(where: {
                        $0.localizedName == appName || $0.bundleIdentifier?.localizedCaseInsensitiveContains(appName.lowercased()) == true
                    }) {
                        app.activate()
                    }
                }
            }
        }
    }

    static func runAppleScript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }

    static func runAppleScriptReturningBool(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output == "true"
    }
}

struct InfoBlock: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.5)
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings Panel (Inline Horizontal Nav)

struct SettingsInlinePanel: View {
    @EnvironmentObject var store: AgentStore
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("appLanguage") private var appLanguage = "Auto"
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("globalHotkey") private var globalHotkey = "⌥ + M"

    private var geminiKeyFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mission-control/gemini-key.txt")
    }

    private func syncApiKey() {
        // Load from gemini-key.txt if AppStorage is empty
        if apiKey.isEmpty, let key = try? String(contentsOf: geminiKeyFile, encoding: .utf8) {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { apiKey = trimmed }
        }
    }

    private func saveApiKey() {
        let dir = geminiKeyFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .write(to: geminiKeyFile, atomically: true, encoding: .utf8)
    }
    
    @State private var selectedTab: String = "账户"
    @State private var showApiKey = false
    @State private var isHoveringClose = false
    
    // Hotkey Recording States
    @State private var isRecordingHotkey = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Header Row: Close button on the right
            HStack {
                Spacer()
                Button(action: { 
                    stopRecording() // ensure we don't leak monitor
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
                        store.viewState = .sessionList 
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(isHoveringClose ? 0.9 : 0.6))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(isHoveringClose ? 0.15 : 0.1), in: Circle())
                        .scaleEffect(isHoveringClose ? 1.05 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        isHoveringClose = hovering
                    }
                    if hovering { NSCursor.pointingHand.set() }
                    else { NSCursor.arrow.set() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Navigation Pill Bar
            HStack(spacing: 8) {
                TopTabButton(title: t("账户"), isSelected: selectedTab == "账户") { switchTab("账户") }
                TopTabButton(title: t("系统"), isSelected: selectedTab == "系统") { switchTab("系统") }
            }
            .padding(6)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.bottom, 24)
            .padding(.top, -14)
            
    // Content Area
    ZStack(alignment: .top) {
        if selectedTab == "账户" {
            accountTab
                .transition(.opacity)
        } else if selectedTab == "系统" {
            systemTab
                .transition(.opacity)
        }
    }
    .animation(.easeInOut(duration: 0.3), value: selectedTab)
    
    Spacer(minLength: 0)
}
.frame(width: 420, height: 260)
.background(.ultraThinMaterial)
.background(Color.black.opacity(0.3))
.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
)
.padding(.bottom, 12)
.environment(\.colorScheme, .dark)
.onDisappear { stopRecording() }
.onAppear { syncApiKey() }
.onChange(of: apiKey) { _ in saveApiKey() }
}

// MARK: - Translation Helper
private func t(_ cnKey: String) -> String {
    let isEn = (appLanguage == "En")
    switch cnKey {
    case "账户": return isEn ? "Account" : "账户"
    case "系统": return isEn ? "System" : "系统"
    case "快捷键": return isEn ? "Hotkeys" : "快捷键"
    case "API KEY": return "API KEY"
    case "Secret Token...": return isEn ? "Paste Key Here..." : "在此粘贴 API 密钥..."
    case "该凭证已安全储存于本地钥匙串中，仅用作 AI 引擎推理。": 
        return isEn ? "This credential is securely stored in local keychain for AI inference." : "该凭证已安全储存于本地钥匙串中，仅用作 AI 引擎推理。"
    case "语言 (Language)": return isEn ? "Language" : "语言 (Language)"
    case "开机自动启动": return isEn ? "Launch at Login" : "开机自动启动"
    case "请键入快捷键": return isEn ? "Type Shortcut..." : "请键入快捷键"
    case "无": return isEn ? "None" : "无"
    case "按下 ESC 键取消": return isEn ? "Press ESC to Cancel" : "按下 ESC 键取消"
    case "已设置": return isEn ? "Configured" : "已设置"
    case "点击上方按钮修改": return isEn ? "Click above to modify" : "点击上方按钮修改"
    case "API_HINT_EMPTY": return isEn ? "Please paste your API Key to start." : "请在上方粘贴 API 密钥以激活"
    case "API_HINT_SET": return isEn ? "API Key active. Type above to replace." : "密钥已启用。直接输入即可覆盖更新"
    default: return cnKey
    }
}

// MARK: - Navigation Control
private func switchTab(_ tab: String) {
    stopRecording()
    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
        selectedTab = tab
    }
}

// MARK: - Hotkey Monitor Logic
private func startRecording() {
    // Prompt for Accessibility permission when user tries to set hotkey
    let trusted = AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    )
    if !trusted { return }
    isRecordingHotkey = true
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        var keys = [String]()
        let flags = event.modifierFlags
        
        if flags.contains(.control) { keys.append("⌃") }
        if flags.contains(.option) { keys.append("⌥") }
        if flags.contains(.shift) { keys.append("⇧") }
        if flags.contains(.command) { keys.append("⌘") }
        
        if event.keyCode == 53 { // ESC key to cancel
            stopRecording()
            return nil
        }
        
        if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            if event.keyCode == 49 { keys.append("Space") }
            else if event.keyCode == 36 { keys.append("Enter") }
            else { keys.append(chars) }
        }
        
        let result = keys.joined(separator: " + ")
        if !result.isEmpty {
            globalHotkey = result
        }
        
        stopRecording()
        return nil
    }
}

private func stopRecording() {
    isRecordingHotkey = false
    if let monitor = eventMonitor {
        NSEvent.removeMonitor(monitor)
        eventMonitor = nil
    }
}

// MARK: - Tab Views
@ViewBuilder
private var accountTab: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(t("API KEY"))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
            .tracking(0.5)
        
        HStack(spacing: 8) {
            if showApiKey {
                TextField(t("Secret Token..."), text: $apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                SecureField(t("Secret Token..."), text: $apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
            Button(action: { showApiKey.toggle() }) {
                Image(systemName: showApiKey ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        
        if apiKey.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                Text(t("API_HINT_EMPTY"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.937, green: 0.624, blue: 0.153))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.937, green: 0.624, blue: 0.153).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 4)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                Text(t("API_HINT_SET"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.365, green: 0.792, blue: 0.647))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.365, green: 0.792, blue: 0.647).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 4)
        }
        
        Text(t("该凭证已安全储存于本地钥匙串中，仅用作 AI 引擎推理。"))
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
            .lineSpacing(2)
            .padding(.top, 4)
    }
    .padding(.horizontal, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}

@ViewBuilder
private var systemTab: some View {
    VStack(alignment: .leading, spacing: 20) {
        // Language Selection
        HStack {
            Text(t("语言 (Language)"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Picker("", selection: $appLanguage) {
                Text("Auto").tag("Auto")
                Text("English").tag("En")
                Text("中文").tag("Zh")
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }

    .padding(.horizontal, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}

}

}

// Custom Bouncy Button Style
struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// Top Nav Button Helper Component
struct TopTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.15) : (isHovering ? Color.white.opacity(0.05) : Color.clear))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
            if hovering { NSCursor.pointingHand.set() }
            else { NSCursor.arrow.set() }
        }
    }
}
