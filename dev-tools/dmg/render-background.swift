import AppKit

// Native typography and SF Symbols; Finder supplies the actual draggable icons.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for dark in [false, true] {
    let size = NSSize(width: 660, height: 400)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1320, pixelsHigh: 800,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let primary = dark ? NSColor(white: 0.95, alpha: 1) : NSColor(white: 0.14, alpha: 1)
    let secondary = dark ? NSColor(white: 0.66, alpha: 1) : NSColor(white: 0.43, alpha: 1)
    (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(red: 0.98, green: 0.975, blue: 0.96, alpha: 1)).setFill()
    NSRect(origin: .zero, size: size).fill()
    func label(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (text as NSString).draw(in: NSRect(x: 30, y: 400-y-36, width: 600, height: 36),
                               withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    label("KeyPath", y: 32, font: .systemFont(ofSize: 15, weight: .semibold),
          color: dark ? NSColor.systemOrange : NSColor(red: 0.65, green: 0.30, blue: 0.05, alpha: 1))
    label("Make your keyboard yours.", y: 66, font: .systemFont(ofSize: 28, weight: .semibold), color: primary)
    label("Drag KeyPath to Applications to install.", y: 110,
          font: .systemFont(ofSize: 15), color: secondary)
    if let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 28, weight: .medium)) {
        let tinted = NSImage(size: arrow.size)
        tinted.lockFocus()
        secondary.setFill()
        NSRect(origin: .zero, size: arrow.size).fill()
        arrow.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: 314, y: 400-220-14, width: 32, height: 28))
    }
    label("Then open KeyPath from Applications to get started.", y: 340,
          font: .systemFont(ofSize: 13), color: secondary)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("installer-\(dark ? "dark" : "light")@2x.png"))
}
