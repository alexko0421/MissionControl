import AppKit
import SwiftUI

class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Always on top
        level = .floating
        isFloatingPanel = true

        // Transparent titlebar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Transparent background — let NSVisualEffectView handle vibrancy
        isOpaque = false
        backgroundColor = .clear

        // Don't steal focus, don't hide on deactivate
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isMovable = true
    }

    override var canBecomeKey: Bool { true }
}

/// Wraps SwiftUI content with a proper NSVisualEffectView for real macOS vibrancy
class VibrancyHostingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private let effectView: NSVisualEffectView

    init(rootView: Content) {
        self.hostingView = NSHostingView(rootView: rootView)
        self.effectView = NSVisualEffectView()
        super.init(frame: .zero)

        // Configure vibrancy
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 22
        effectView.layer?.masksToBounds = true

        // Layout
        effectView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(effectView)
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
