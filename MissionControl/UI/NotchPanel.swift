import AppKit

class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isMovable = false
    }

    // Allow key status for interactions (buttons, text fields)
    // but use nonactivatingPanel style so it doesn't steal app focus
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Accept first mouse click without needing to focus first
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let origin = NotchDetector.panelOrigin(for: screen, panelSize: frame.size)
        setFrameOrigin(origin)
    }
}
