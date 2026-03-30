import SwiftUI

@main
struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private var store = AgentStore()
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the floating panel
        let contentRect = NSRect(x: 0, y: 0, width: 10, height: 10)
        panel = FloatingPanel(contentRect: contentRect)

        let hostingView = NSHostingView(rootView:
            ContentView()
                .environmentObject(store)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        // Position near top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 200
            let y = screenFrame.maxY - 45
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()

        // Start data watching
        store.startWatching()

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Register global hotkey
        registerGlobalHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopWatching()
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Global Hotkey

    private func registerGlobalHotkey() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let stored = UserDefaults.standard.string(forKey: "globalHotkey") ?? "⌥ + Space"
            if self.eventMatchesHotkey(event, hotkey: stored) {
                Task { @MainActor in
                    self.togglePanel()
                }
            }
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func eventMatchesHotkey(_ event: NSEvent, hotkey: String) -> Bool {
        // Parse stored hotkey string like "⌥ + Space" or "⌘ + ⇧ + M"
        let parts = hotkey.components(separatedBy: " + ").map { $0.trimmingCharacters(in: .whitespaces) }

        var requiredModifiers: NSEvent.ModifierFlags = []
        var requiredKey: String?

        for part in parts {
            switch part {
            case "⌃": requiredModifiers.insert(.control)
            case "⌥": requiredModifiers.insert(.option)
            case "⇧": requiredModifiers.insert(.shift)
            case "⌘": requiredModifiers.insert(.command)
            case "Space": requiredKey = " "
            case "Enter": requiredKey = "\r"
            default: requiredKey = part.lowercased()
            }
        }

        // Check modifiers match (only the ones we care about)
        let relevantFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let eventMods = event.modifierFlags.intersection(relevantFlags)
        guard eventMods == requiredModifiers else { return false }

        // Check key matches
        if let key = requiredKey {
            let eventKey = event.keyCode == 49 ? " " :
                           event.keyCode == 36 ? "\r" :
                           (event.charactersIgnoringModifiers?.lowercased() ?? "")
            return eventKey == key
        }

        return false
    }
}
