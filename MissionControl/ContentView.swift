import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AgentStore

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.055, blue: 0.059)
                .ignoresSafeArea()

            if store.selectedAgentId != nil {
                DetailContainerView()
                    .transition(.opacity)
            } else {
                ListContainerView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.selectedAgentId)
    }
}
