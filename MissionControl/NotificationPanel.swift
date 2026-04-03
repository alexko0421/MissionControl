import AppKit
import SwiftUI

/// A separate floating window that appears as a toast notification
/// when an agent completes or needs attention.
class NotificationPanel {
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    static let shared = NotificationPanel()

    func show(alert: AgentStore.AgentAlert) {
        // Dismiss any existing notification
        dismiss()

        let view = NotificationBanner(alert: alert, onDismiss: { [weak self] in
            self?.dismiss()
        })

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 72)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 72),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating + 1  // Above the main floating panel
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView

        // Position: top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 180
            let y = screenFrame.maxY - 90
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Animate in
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        self.panel = panel

        // Auto-dismiss after 4 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let panel = panel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
        })
    }
}

// MARK: - Notification Banner View

struct NotificationBanner: View {
    let alert: AgentStore.AgentAlert
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(iconColor)

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.agentName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(alert.task)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Status badge
            Text(statusLabel)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(iconColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(iconColor.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .background(bgColor.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(iconColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .environment(\.colorScheme, .dark)
        .onTapGesture { onDismiss() }
    }

    private var iconName: String {
        switch alert.newStatus {
        case .done: return "checkmark.circle.fill"
        case .blocked: return "exclamationmark.circle.fill"
        default: return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch alert.newStatus {
        case .done: return Color(red: 0.30, green: 0.85, blue: 0.50)
        case .blocked: return Color(red: 0.937, green: 0.624, blue: 0.153)
        default: return Color(red: 0.365, green: 0.631, blue: 0.847)
        }
    }

    private var bgColor: Color {
        switch alert.newStatus {
        case .done: return Color(red: 0.10, green: 0.25, blue: 0.15)
        case .blocked: return Color(red: 0.30, green: 0.20, blue: 0.08)
        default: return Color(red: 0.10, green: 0.18, blue: 0.28)
        }
    }

    private var statusLabel: String {
        switch alert.newStatus {
        case .done: return "DONE"
        case .blocked: return "ACTION"
        default: return "INFO"
        }
    }
}
