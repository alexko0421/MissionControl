import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        ZStack {
            // Base layer: Terminal or Summary
            Group {
                switch store.viewState {
                case .terminal, .sessionList:
                    if let agent = store.priorityAgent {
                        TerminalView(agent: agent)
                    } else {
                        emptyState
                    }
                case .summary(let agentId):
                    if let agent = store.agents.first(where: { $0.id == agentId }) {
                        SummaryView(agent: agent)
                    } else {
                        emptyState
                    }
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: store.viewStateKey)

            // Overlay layer: Session list
            if case .sessionList = store.viewState {
                SessionListOverlay()
                    .transition(.opacity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("未有 Session")
                .font(.system(size: 13))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
