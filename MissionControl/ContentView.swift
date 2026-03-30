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
                        Text(agent.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )

                    // Task text
                    Text(agent.task)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: agent.task)
                    
                    Spacer(minLength: 0)
                } else {
                    // Empty state
                    HStack(spacing: 5) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Idle")
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

                    Text("Waiting for task...")
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
        .environment(\.colorScheme, .dark)
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
                ForEach(store.sortedAgents) { agent in
                    SessionRow(agent: agent)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
                                store.showSummary(for: agent.id)
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
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.bottom, 12)
        .environment(\.colorScheme, .dark)
        .onAppear { Agent.displayLanguage = appLanguage }
        .onChange(of: appLanguage) { Agent.displayLanguage = $0 }
    }
}

struct SessionRow: View {
    let agent: Agent
    @State private var isHovered = false

    var body: some View {
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
        .contentShape(Rectangle())
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
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.bottom, 12)
        .environment(\.colorScheme, .dark)
    }

    private func jumpToSession(agent: Agent) {
        guard let target = agent.tmuxTarget else { return }
        Task.detached {
            // Select the tmux window/pane
            let selectCmd = "tmux select-window -t \"\(target)\" 2>/dev/null; tmux select-pane -t \"\(target)\" 2>/dev/null"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", selectCmd]
            try? process.run()
            process.waitUntilExit()

            // Bring Terminal.app to front
            let script = "tell application \"Terminal\" to activate"
            let appleScript = Process()
            appleScript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            appleScript.arguments = ["-e", script]
            try? appleScript.run()
            appleScript.waitUntilExit()
        }
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
    @AppStorage("globalHotkey") private var globalHotkey = "⌥ Space"
    
    @State private var selectedTab: String = "账户"
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
                TopTabButton(title: t("快捷键"), isSelected: selectedTab == "快捷键") { switchTab("快捷键") }
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
        } else if selectedTab == "快捷键" {
            hotkeyTab
                .transition(.opacity)
        }
    }
    .animation(.easeInOut(duration: 0.3), value: selectedTab)
    
    Spacer(minLength: 0)
}
.frame(width: 420, height: 240)
.background(.ultraThinMaterial)
.background(Color.black.opacity(0.3))
.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
)
.shadow(color: .black.opacity(0.2), radius: 20, y: 10)
.padding(.bottom, 12)
.environment(\.colorScheme, .dark)
.onDisappear { stopRecording() }
}

// MARK: - Translation Helper
private func t(_ cnKey: String) -> String {
    let isEn = (appLanguage == "En")
    switch cnKey {
    case "账户": return isEn ? "Account" : "账户"
    case "系统": return isEn ? "System" : "系统"
    case "快捷键": return isEn ? "Hotkeys" : "快捷键"
    case "API KEY": return "API KEY"
    case "Secret Token...": return isEn ? "Secret Token..." : "输入密钥..."
    case "该凭证已安全储存于本地钥匙串中，仅用作 AI 引擎推理。": 
        return isEn ? "This credential is securely stored in local keychain for AI inference." : "该凭证已安全储存于本地钥匙串中，仅用作 AI 引擎推理。"
    case "语言 (Language)": return isEn ? "Language" : "语言 (Language)"
    case "开机自动启动": return isEn ? "Launch at Login" : "开机自动启动"
    case "请键入快捷键": return isEn ? "Type Shortcut..." : "请键入快捷键"
    case "无": return isEn ? "None" : "无"
    case "按下 ESC 键取消": return isEn ? "Press ESC to Cancel" : "按下 ESC 键取消"
    case "点击上方按钮修改": return isEn ? "Click above to modify" : "点击上方按钮修改"
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
        
        SecureField(t("Secret Token..."), text: $apiKey)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        
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

        // Launch at Login
        HStack {
            Text(t("开机自动启动"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Toggle("", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .scaleEffect(0.9)
                .tint(.white.opacity(0.7))
        }
    }
    .padding(.horizontal, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}

@ViewBuilder
private var hotkeyTab: some View {
    VStack(spacing: 24) {
        Button(action: { 
            if isRecordingHotkey { stopRecording() } 
            else { startRecording() }
        }) {
            let strokeColor = isRecordingHotkey ? Color.blue.opacity(0.6) : Color.white.opacity(0.12)
            let bgColor = isRecordingHotkey ? Color.blue.opacity(0.1) : Color(white: 0.12)
            
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 18))
                    .foregroundStyle(isRecordingHotkey ? Color.blue : .white)
                Text(isRecordingHotkey ? t("请键入快捷键") : (globalHotkey.isEmpty ? t("无") : globalHotkey))
            }
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 36)
            .padding(.vertical, 16)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(strokeColor, lineWidth: isRecordingHotkey ? 2 : 1)
            )
            .shadow(color: isRecordingHotkey ? Color.blue.opacity(0.15) : Color.black.opacity(0.25), radius: 10, y: 5)
            .scaleEffect(isRecordingHotkey ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecordingHotkey)
        }
        .buttonStyle(BouncyButtonStyle())

        HStack(spacing: 6) {
            Image(systemName: "pencil")
            Text(isRecordingHotkey ? t("按下 ESC 键取消") : t("点击上方按钮修改"))
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.4))
    }
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
