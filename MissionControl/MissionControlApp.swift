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
    private var localMonitor: Any?
    private var statusItem: NSStatusItem?

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
            let panelWidth = panel.frame.width > 10 ? panel.frame.width : 400
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.maxY - 45
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Re-center when panel resizes
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self = self, let screen = NSScreen.main else { return }
            let screenFrame = screen.visibleFrame
            let panelFrame = self.panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            self.panel.setFrameOrigin(NSPoint(x: x, y: panelFrame.origin.y))
        }
        panel.orderFrontRegardless()

        // Start data watching
        store.startWatching()

        // Register keyboard shortcuts (⌘1-9 for options, ⌘Y/⌘N for approve/deny)
        registerShortcuts()

        // Show in Dock and menu bar
        NSApp.setActivationPolicy(.regular)

        // Create Status Bar Icon
        setupStatusBar()

        // Global hotkey disabled for now
        // registerGlobalHotkey()
    }

    private func registerShortcuts() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            // Only handle ⌘ shortcuts
            guard event.modifierFlags.contains(.command) else { return event }

            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

            // ⌘Y = approve/allow
            if key == "y" {
                Task { @MainActor in self.handleApproveShortcut() }
                return nil
            }
            // ⌘N = deny/reject
            if key == "n" {
                Task { @MainActor in self.handleDenyShortcut() }
                return nil
            }
            // ⌘1-9 = select option
            if let num = Int(key), num >= 1 && num <= 9 {
                Task { @MainActor in self.handleOptionShortcut(num) }
                return nil
            }

            return event
        }
    }

    @MainActor
    private func handleApproveShortcut() {
        // Find first agent with pending question/permission and approve
        if let agent = store.agents.first(where: { $0.pendingQuestion != nil }) {
            if let q = agent.pendingQuestion {
                if let yesOpt = q.options.first(where: { $0.sendKey == "y" || $0.sendKey == "1" || $0.sendKey == "Enter" }) {
                    store.respondQuestion(agentId: agent.id, option: yesOpt)
                    return
                }
            }
        }
        if let agent = store.agents.first(where: { $0.pendingPermission != nil }),
           let perm = agent.pendingPermission {
            store.respondPermission(agentId: agent.id, requestId: perm.id, choice: .yes)
        }
    }

    @MainActor
    private func handleDenyShortcut() {
        if let agent = store.agents.first(where: { $0.pendingQuestion != nil }) {
            if let q = agent.pendingQuestion {
                if let noOpt = q.options.first(where: { $0.sendKey == "n" || $0.sendKey == "3" }) ?? q.options.last {
                    store.respondQuestion(agentId: agent.id, option: noOpt)
                    return
                }
            }
        }
        if let agent = store.agents.first(where: { $0.pendingPermission != nil }),
           let perm = agent.pendingPermission {
            store.respondPermission(agentId: agent.id, requestId: perm.id, choice: .no)
        }
    }

    @MainActor
    private func handleOptionShortcut(_ num: Int) {
        if let agent = store.agents.first(where: { $0.pendingQuestion != nil }) {
            if let q = agent.pendingQuestion,
               let opt = q.options.first(where: { $0.id == num }) {
                store.respondQuestion(agentId: agent.id, option: opt)
            }
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.title = ""
            button.image = makeMImage()
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "MissionControl"
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示主面板 (Show)", action: #selector(showDashboard), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 (Quit)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }

    @objc private func showDashboard() {
        togglePanel()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    /// Renders a bold rounded "M" as a template NSImage sized for the menu bar.
    /// Using an image (rather than button.title) guarantees perfect vertical
    /// alignment with every other icon on the bar.
    private func makeMImage() -> NSImage {
        // Menu bar icons are drawn at 18pt; @2x = 36px
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let fontSize: CGFloat = 16
            let sysFont = NSFont.systemFont(ofSize: fontSize, weight: .black)
            let font: NSFont
            if let desc = sysFont.fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: desc, size: fontSize) ?? sysFont
            } else {
                font = sysFont
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black  // template image; macOS will tint automatically
            ]
            let str = "M" as NSString
            let strSize = str.size(withAttributes: attrs)
            let pt = NSPoint(
                x: (rect.width  - strSize.width)  / 2,
                y: (rect.height - strSize.height) / 2
            )
            str.draw(at: pt, withAttributes: attrs)
            return true
        }
        // Mark as template so macOS auto-tints it for light / dark menu bar
        image.isTemplate = true
        return image
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "MissionControl",
            .credits: NSAttributedString(
                string: "GitHub: https://github.com/alexko0421/MissionControl\n开发者: Ko Chunlong\n开源授权: MIT License",
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
            )
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopWatching()
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Global Hotkey

    private func registerGlobalHotkey() {
        // Check Accessibility permission silently — don't prompt on launch
        let trusted = AXIsProcessTrustedWithOptions(nil)
        if !trusted {
            print("⚠ Accessibility permission not granted — global hotkey disabled. Grant in System Settings → Privacy & Security → Accessibility")
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let stored = UserDefaults.standard.string(forKey: "globalHotkey") ?? "⌥ + M"
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
