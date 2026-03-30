import SwiftUI

struct SummaryView: View {
    let agent: Agent
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack(spacing: 10) {
                Button(action: { store.showTerminal() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("返回")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                StatusBadge(status: agent.status)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Summary content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Agent name
                    HStack(spacing: 10) {
                        StatusDot(status: agent.status)
                        Text(agent.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    // Task
                    SummarySection(label: "任務") {
                        Text(agent.task)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineSpacing(4)
                    }

                    // Summary
                    SummarySection(label: "最新摘要") {
                        Text(agent.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineSpacing(4)
                    }

                    // Next action
                    SummarySection(label: "下一步") {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AgentStatus.running.color)
                            Text(agent.nextAction)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.7))
                                .lineSpacing(4)
                        }
                    }

                    // Worktree info (if available)
                    if let worktree = agent.worktree {
                        SummarySection(label: "Worktree") {
                            Text(worktree)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.5))
                        }
                    }
                }
                .padding(18)
            }
        }
    }
}

struct SummarySection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))
                .textCase(.uppercase)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}
