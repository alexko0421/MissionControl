import SwiftUI

@main
struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Standard macOS Settings scene
        Settings {
            SettingsView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var store = AgentStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the floating panel — small initial size, content drives actual size
        let contentRect = NSRect(x: 0, y: 0, width: 10, height: 10)
        panel = FloatingPanel(contentRect: contentRect)

        // Set SwiftUI content
        let hostingView = NSHostingView(rootView:
            ContentView()
                .environmentObject(store)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        // Position near top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            // Keep the exact original X center the user is used to
            let x = screenFrame.midX - 200
            // Push it higher up near the menu bar
            let y = screenFrame.maxY - 45
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
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
