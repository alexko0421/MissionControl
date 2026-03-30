import SwiftUI

@main
struct MissionControlApp: App {
    @StateObject private var store = AgentStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onAppear  { store.startWatching() }
                .onDisappear { store.stopWatching() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 820, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
