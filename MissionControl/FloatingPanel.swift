import AppKit
import SwiftUI

class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true

        // Fully transparent window — each SwiftUI view handles its own glass
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isMovable = true
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - NSViewRepresentable for real macOS vibrancy

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Transparent container that hosts SwiftUI without any background

class TransparentContainerView: NSView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        // Draw nothing — fully transparent
    }
}

func makeTransparentHosting<Content: View>(_ content: Content) -> NSView {
    let container = TransparentContainerView()
    container.wantsLayer = true
    container.layer?.backgroundColor = .clear

    let controller = NSHostingController(rootView: content)
    controller.view.wantsLayer = true
    controller.view.layer?.backgroundColor = .clear
    controller.view.frame = container.bounds
    controller.view.autoresizingMask = [.width, .height]

    // Remove the default hosting view background
    DispatchQueue.main.async {
        controller.view.subviews.forEach { sub in
            sub.wantsLayer = true
            sub.layer?.backgroundColor = .clear
        }
    }

    container.addSubview(controller.view)
    return container
}
