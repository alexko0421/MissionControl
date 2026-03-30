import SwiftUI

// MARK: - Detail Container (sidebar + main)

struct DetailContainerView: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 200)
            Divider().background(Color.white.opacity(0.06))
            if let agent = store.selectedAgent {
                AgentDetailView(agent: agent)
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()

            VStack(alignment: .leading, spacing: 0) {
                Text("所有 Agent")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                Divider().background(Color.white.opacity(0.04))

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.agents) { agent in
                            SidebarRow(agent: agent, isActive: store.selectedAgentId == agent.id)
                                .onTapGesture {
                                    withAnimation { store.selectedAgentId = agent.id }
                                }
                        }
                    }
                }
            }
            .background(Color(red: 0.075, green: 0.075, blue: 0.078))
        }
    }
}

struct SidebarRow: View {
    let agent: Agent
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            StatusDot(status: agent.status)
            Text(agent.name)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(isActive ? 0.9 : 0.65))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Rectangle()
                .fill(Color.white.opacity(isActive ? 0.06 : (isHovered ? 0.03 : 0)))
                .overlay(alignment: .leading) {
                    if isActive {
                        Rectangle()
                            .fill(Color(red: 0.365, green: 0.792, blue: 0.647))
                            .frame(width: 2)
                    }
                }
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}

// MARK: - Agent Detail Main

struct AgentDetailView: View {
    let agent: Agent
    @EnvironmentObject var store: AgentStore
    @State private var commandText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                StatusDot(status: agent.status)

                Text(agent.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))

                StatusBadge(status: agent.status)
                Spacer()

                Button("← 返回") {
                    withAnimation { store.selectedAgentId = nil }
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.22))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) {
                Divider().background(Color.white.opacity(0.06))
            }

            // Scrollable content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // Summary block
                        DetailBlock(label: "最新摘要") {
                            Text(agent.summary)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.65))
                                .lineSpacing(4)
                        }

                        // Terminal block
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(agent.terminalLines) { line in
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(line.type.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 1)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.039, green: 0.039, blue: 0.043))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                )
                        )

                        // Next action
                        HStack(alignment: .top, spacing: 6) {
                            Text("→")
                                .font(.system(size: 13))
                                .foregroundColor(Color(red: 0.365, green: 0.792, blue: 0.647))
                            Text(agent.nextAction)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.45))
                                .lineSpacing(3)
                        }
                        .padding(.top, 2)

                        Color.clear.frame(height: 4).id("bottom")
                    }
                    .padding(18)
                }
                .onChange(of: agent.terminalLines.count) { _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }

            // Input area
            HStack(spacing: 8) {
                TextField("輸入下一步指令...", text: $commandText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.82))
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(inputFocused
                                        ? Color(red: 0.365, green: 0.792, blue: 0.647).opacity(0.4)
                                        : Color.white.opacity(0.1),
                                        lineWidth: 0.5)
                            )
                    )
                    .onSubmit { sendCommand() }

                Button(action: sendCommand) {
                    Text("發送 →")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.365, green: 0.792, blue: 0.647))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0.365, green: 0.792, blue: 0.647).opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(red: 0.365, green: 0.792, blue: 0.647).opacity(0.3), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(commandText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(red: 0.055, green: 0.055, blue: 0.059))
            .overlay(alignment: .top) {
                Divider().background(Color.white.opacity(0.06))
            }
        }
    }

    private func sendCommand() {
        let text = commandText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.sendCommand(text, to: agent)
        commandText = ""
    }
}

// MARK: - Helpers

struct DetailBlock<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

struct StatusBadge: View {
    let status: AgentStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 10))
            .foregroundColor(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
