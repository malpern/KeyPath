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
let artwork = NSImage(contentsOf: directory.appendingPathComponent("dmg-bg-keyboard-clean.png"))!
artwork.draw(in: NSRect(origin: .zero, size: size))
// Finder uses dark native filenames over image backgrounds. Small warm keycap
// plates keep those real labels readable without baking in duplicate text.
for center: CGFloat in [180, 480] {
    let plate = NSRect(x: center - 62, y: 400 - 253 - 30, width: 124, height: 30)
    NSColor(red: 0.96, green: 0.91, blue: 0.82, alpha: 1).setFill()
    NSBezierPath(roundedRect: plate, xRadius: 8, yRadius: 8).fill()
}
func label(_ text: String, y: CGFloat, height: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (text as NSString).draw(in: NSRect(x: 24, y: 400-y-height, width: 612, height: height),
                           withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}
let serif = NSFont.systemFont(ofSize: 42, weight: .medium).fontDescriptor.withDesign(.serif)!
label("KeyPath", y: 21, height: 56, font: NSFont(descriptor: serif, size: 42)!, color: .white)
label("Keys that do more.", y: 80, height: 26,
      font: NSFontManager.shared.convert(.systemFont(ofSize: 15), toHaveTrait: .italicFontMask),
      color: NSColor(white: 0.88, alpha: 1))
if let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 28, weight: .regular)) {
    let tinted = NSImage(size: arrow.size)
    tinted.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: arrow.size).fill()
    arrow.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
    tinted.unlockFocus()
    tinted.draw(in: NSRect(x: 314, y: 400-200-14, width: 32, height: 28))
}
label("Drag KeyPath to Applications to install.", y: 348, height: 24,
      font: .systemFont(ofSize: 14, weight: .medium), color: .white)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("installer-branded@2x.png"))
