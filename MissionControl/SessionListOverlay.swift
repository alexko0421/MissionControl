import SwiftUI

struct SessionListOverlay: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        ZStack {
            // Dimmed backdrop — tap to dismiss
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { store.showTerminal() }

            // Session list card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("所有 Session")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                    Spacer()

                    // Stats
                    HStack(spacing: 12) {
                        StatPill(count: store.blockedCount, color: AgentStatus.blocked.color)
                        StatPill(count: store.runningCount, color: AgentStatus.running.color)
                        StatPill(count: store.doneCount, color: AgentStatus.done.color)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Agent list
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.sortedAgents) { agent in
                            SessionCard(agent: agent)
                                .onTapGesture {
                                    store.showSummary(for: agent.id)
                                }
                        }
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
            .padding(24)
        }
    }
}

struct SessionCard: View {
    let agent: Agent
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: agent.status)

            Text(agent.name)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)

            Spacer()

            Text(agent.timeAgo)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(isHovered ? 0.08 : 0.04))
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}

struct StatPill: View {
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
