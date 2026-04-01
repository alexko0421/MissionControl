import Cocoa
import CoreText

func generateTextIcon() {
    let size = CGSize(width: 1024, height: 1024)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let savedContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    
    let ctx = context.cgContext
    
    // Background Slate Blue
    NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.55, alpha: 1.0).setFill()
    let bgRect = NSRect(origin: .zero, size: size)
    NSBezierPath(roundedRect: bgRect, xRadius: 224, yRadius: 224).fill()

    // 1. Revert to original HUGE font size
    let fontSize: CGFloat = 760
    let systemFont = NSFont.systemFont(ofSize: fontSize, weight: .black)
    
    // Apply rounded design
    let font: NSFont
    if let roundedDesc = systemFont.fontDescriptor.withDesign(.rounded) {
         font = NSFont(descriptor: roundedDesc, size: fontSize) ?? systemFont
    } else {
         font = systemFont
    }
    
    // 2. Prepare text drawing via CoreText to get exact ink boundaries
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let attrString = NSAttributedString(string: "M", attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString)
    
    // Get the EXACT physical pixel boundaries of the printed 'M' (ignoring whitespace pads)
    let imageBounds = CTLineGetImageBounds(line, ctx)
    
    // Calculate offset to precisely center the visual bounds pixel-perfectly
    let centerX = size.width / 2.0
    let centerY = size.height / 2.0
    
    let xOffset = centerX - imageBounds.midX
    let yOffset = centerY - imageBounds.midY
    
    context.saveGraphicsState()
    
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.shadowBlurRadius = 30.0
    shadow.set()
    
    // Draw string using CoreText exactly at offset
    ctx.textPosition = CGPoint(x: xOffset, y: yOffset)
    CTLineDraw(line, ctx)
    
    context.restoreGraphicsState()

    NSGraphicsContext.current = savedContext

    let pngData = rep.representation(using: .png, properties: [:])!
    let outPath = "/Users/kochunlong/Library/Mobile Documents/com~apple~CloudDocs/MissionControl/PerfectGeometric_M.png"
    try! pngData.write(to: URL(fileURLWithPath: outPath))
    print("Saved PerfectGeometric_M")
}

generateTextIcon()
