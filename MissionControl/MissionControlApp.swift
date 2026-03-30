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
        // Create the floating panel — small initial size, content drives actual size
        let contentRect = NSRect(x: 0, y: 0, width: 10, height: 10)
        panel = FloatingPanel(contentRect: contentRect)

        // Transparent container — bypasses NSHostingView's opaque background
        panel.contentView = makeTransparentHosting(
            ContentView().environmentObject(store)
        )

        // Position near top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 200
            let y = screenFrame.maxY - 80
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
