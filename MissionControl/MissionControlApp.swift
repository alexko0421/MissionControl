import SwiftUI

@main
struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty settings scene — the panel is managed by AppDelegate
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var store = AgentStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the floating panel
        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 400)
        panel = FloatingPanel(contentRect: contentRect)

        // Set SwiftUI content
        let contentView = ContentView()
            .environmentObject(store)

        panel.contentView = NSHostingView(rootView: contentView)

        // Center and show
        panel.center()
        panel.orderFrontRegardless()

        // Start data watching
        store.startWatching()

        // Hide dock icon — this is a floating utility
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopWatching()
    }
}
