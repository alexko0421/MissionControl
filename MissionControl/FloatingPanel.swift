import AppKit

class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
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
}
