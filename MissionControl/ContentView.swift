import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(spacing: 6) {
            CapsuleBar()

            if case .sessionList = store.viewState {
                SessionListPanel()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if case .summary(let agentId) = store.viewState {
                if let agent = store.agents.first(where: { $0.id == agentId }) {
                    SummaryPanel(agent: agent)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.viewStateKey)
        .fixedSize()
    }
}

// MARK: - Glass Capsule Background

struct GlassCapsule: View {
    var body: some View {
        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}

struct GlassRoundedRect: View {
    var cornerRadius: CGFloat = 14

    var body: some View {
        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Capsule Bar

struct CapsuleBar: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { store.toggleSessionList() }) {
                Image(systemName: store.isSessionListOpen ? "xmark" : "line.3.horizontal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            if let agent = store.priorityAgent {
                StatusDot(status: agent.status)

                Text(agent.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)

                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.primary.opacity(0.12))
                    .frame(width: 1, height: 14)

                Text(agent.task)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .leading)
            } else {
                Text("未有 Session")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(GlassCapsule())
    }
}

// MARK: - Session List Panel

struct SessionListPanel: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(spacing: 2) {
            ForEach(store.sortedAgents) { agent in
                SessionRow(agent: agent)
                    .onTapGesture {
                        store.showSummary(for: agent.id)
                    }
            }
        }
        .padding(8)
        .background(GlassRoundedRect())
    }
}

struct SessionRow: View {
    let agent: Agent
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            StatusDot(status: agent.status)

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)

                Text(agent.task)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(agent.status.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(agent.status.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(agent.status.color.opacity(0.12), in: Capsule())

            Text(agent.timeAgo)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(isHovered ? 0.08 : 0))
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}

// MARK: - Summary Panel

struct SummaryPanel: View {
    let agent: Agent
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusDot(status: agent.status)
                Text(agent.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: { store.showTerminal() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            InfoBlock(label: "任務", text: agent.task)
            InfoBlock(label: "摘要", text: agent.summary)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AgentStatus.running.color)
                    .frame(width: 14)
                Text(agent.nextAction)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineSpacing(3)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(GlassRoundedRect())
    }
}

struct InfoBlock: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.7))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
