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

// MARK: - Transparent NSHostingView (removes default opaque background)

class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Remove the default opaque background added by NSHostingView
        DispatchQueue.main.async {
            self.removeOpaqueBackground(from: self)
        }
    }

    private func removeOpaqueBackground(from view: NSView) {
        if let layer = view.layer {
            layer.backgroundColor = .clear
        }
        for subview in view.subviews {
            removeOpaqueBackground(from: subview)
        }
    }
}
