import SwiftUI

// MARK: - List Container

struct ListContainerView: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            StatsBar()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.agents) { agent in
                        AgentCard(agent: agent)
                            .onTapGesture {
                                withAnimation { store.selectedAgentId = agent.id }
                            }
                    }
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Title Bar

struct TitleBar: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(red: 1, green: 0.357, blue: 0.341)).frame(width: 10, height: 10)
            Circle().fill(Color(red: 1, green: 0.741, blue: 0.180)).frame(width: 10, height: 10)
            Circle().fill(Color(red: 0.157, green: 0.784, blue: 0.251)).frame(width: 10, height: 10)
            Text("任務指揮台")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .padding(.leading, 8)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.102, green: 0.102, blue: 0.106))
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.06))
        }
    }
}

// MARK: - Stats Bar

struct StatsBar: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        HStack(spacing: 16) {
            StatChip(count: store.runningCount, label: "進行中", color: Color(red: 0.365, green: 0.792, blue: 0.647))
            StatChip(count: store.blockedCount, label: "需要你",  color: Color(red: 0.937, green: 0.624, blue: 0.153))
            StatChip(count: store.doneCount,    label: "已完成",  color: Color(red: 0.216, green: 0.541, blue: 0.867))
            Spacer()
            Button(action: { store.loadFromFile() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(red: 0.055, green: 0.055, blue: 0.059))
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.05))
        }
    }
}

struct StatChip: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Text("\(count)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

// MARK: - Agent Card

struct AgentCard: View {
    let agent: Agent
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 11) {
            StatusDot(status: agent.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.82))

                Text(agent.task)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                    .lineLimit(1)
            }

            Spacer()

            Text(agent.timeAgo)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.18))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(isHovered ? 0.12 : 0.07), lineWidth: 0.5)
                )
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}

// MARK: - Status Dot

struct StatusDot: View {
    let status: AgentStatus
    @State private var pulse = false

    var body: some View {
        ZStack {
            if status.hasPulse {
                Circle()
                    .fill(status.color.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 0.6)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
        }
        .frame(width: 12, height: 12)
        .onAppear { if status.hasPulse { pulse = true } }
    }
}
