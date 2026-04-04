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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let origin = NotchDetector.panelOrigin(for: screen, panelSize: frame.size)
        setFrameOrigin(origin)
    }
}
