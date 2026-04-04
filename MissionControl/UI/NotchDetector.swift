import AppKit

struct NotchDetector {
    static func hasNotch(screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            return screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }
        return false
    }

    static func panelOrigin(for screen: NSScreen, panelSize: NSSize) -> NSPoint {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame

        if hasNotch(screen: screen) {
            let x = frame.midX - panelSize.width / 2
            let y = frame.maxY - panelSize.height
            return NSPoint(x: x, y: y)
        } else {
            let x = visibleFrame.midX - panelSize.width / 2
            let y = visibleFrame.maxY - panelSize.height
            return NSPoint(x: x, y: y)
        }
    }
}
