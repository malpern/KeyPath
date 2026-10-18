import AppKit

// Compose the original KeyPath artwork with native, precisely placed typography.
// Finder supplies the actual draggable app and Applications icons.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 660, height: 400)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1320, pixelsHigh: 800,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let artwork = NSImage(contentsOf: directory.appendingPathComponent("dmg-bg-keyboard-legends.png"))!
artwork.draw(in: NSRect(origin: .zero, size: size))
// One shared installation surface supports the drag gesture and keeps
// Finder's mandatory dark filenames readable, without button-like label pills.
let stage = NSRect(x: 110, y: 400 - 145 - 160, width: 440, height: 160)
let surface = NSBezierPath(roundedRect: stage, xRadius: 24, yRadius: 24)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
shadow.shadowBlurRadius = 22
shadow.shadowOffset = NSSize(width: 0, height: -6)
shadow.set()
NSColor(red: 0.96, green: 0.945, blue: 0.91, alpha: 1).setFill()
surface.fill()
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.55).setStroke()
surface.lineWidth = 0.5
surface.stroke()
func label(_ text: String, y: CGFloat, height: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (text as NSString).draw(in: NSRect(x: 24, y: 400-y-height, width: 612, height: height),
                           withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}
let serif = NSFont.systemFont(ofSize: 40, weight: .medium).fontDescriptor.withDesign(.serif)!
label("KeyPath", y: 26, height: 54, font: NSFont(descriptor: serif, size: 40)!, color: .white)
label("Keys that do more.", y: 82, height: 24,
      font: .systemFont(ofSize: 14, weight: .regular),
      color: NSColor(white: 0.76, alpha: 1))
if let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 26, weight: .light)) {
    let tinted = NSImage(size: arrow.size)
    tinted.lockFocus()
    NSColor(red: 0.38, green: 0.32, blue: 0.25, alpha: 1).setFill()
    NSRect(origin: .zero, size: arrow.size).fill()
    arrow.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
    tinted.unlockFocus()
    tinted.draw(in: NSRect(x: 314, y: 400-208-14, width: 32, height: 28))
}
label("Drag KeyPath to Applications to install.", y: 361, height: 24,
      font: .systemFont(ofSize: 13, weight: .regular), color: NSColor(white: 0.78, alpha: 1))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("installer-branded@2x.png"))
