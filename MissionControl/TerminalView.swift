import SwiftUI

struct TerminalView: View {
    let agent: Agent
    @EnvironmentObject var store: AgentStore

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with ☰ button and agent info
            HStack(spacing: 10) {
                Button(action: { store.toggleSessionList() }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                StatusDot(status: agent.status)

                Text(agent.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))

                StatusBadge(status: agent.status)

                Spacer()

                Text(agent.timeAgo)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(agent.terminalLines) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(line.type.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 1)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)

                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: agent.terminalLines.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }
        }
    }
}
