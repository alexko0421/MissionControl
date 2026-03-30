import AppKit

class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Always on top
        level = .floating
        isFloatingPanel = true

        // Transparent titlebar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Semi-transparent background
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)

        // Allow interaction without activating the app
        hidesOnDeactivate = false

        // Remember position
        isMovableByWindowBackground = true

        // Min size
        minSize = NSSize(width: 360, height: 280)
    }
}
