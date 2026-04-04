import AppKit

class NotchPanel: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        // Always on top
        level = .floating
        isFloatingPanel = true

        // Fully transparent — SwiftUI handles all visuals
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Don't steal focus, don't hide on deactivate
        hidesOnDeactivate = false
        isMovableByWindowBackground = true

        // Appear on ALL desktop spaces
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Allow resizing via SwiftUI content
        isMovable = true
    }

    // Allow the panel to become key (for interactions) even as a non-activating panel
    override var canBecomeKey: Bool { true }

    // Accept first mouse click — no need to focus first
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    // MARK: - Notch-aware positioning

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let origin = NotchDetector.panelOrigin(for: screen, panelSize: frame.size)
        setFrameOrigin(origin)
    }
}
