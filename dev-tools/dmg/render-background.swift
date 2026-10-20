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
// A full-height installation column keeps native Finder labels legible while
// preserving the brand artwork as an unobstructed hero on the left.
NSColor(red: 0.91, green: 0.92, blue: 0.93, alpha: 1).setFill()
NSRect(x: 427.5, y: 0, width: 232.5, height: 400).fill()
func label(_ text: String, y: CGFloat, height: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    (text as NSString).draw(in: NSRect(x: 36, y: 400 - y - height, width: 290, height: height),
                            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}

let serif = NSFont.systemFont(ofSize: 40, weight: .medium).fontDescriptor.withDesign(.serif)!
label("KeyPath", y: 40, height: 54, font: NSFont(descriptor: serif, size: 40)!, color: NSColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1))
label("Keys that do more.", y: 91, height: 24,
      font: .systemFont(ofSize: 13, weight: .regular),
      color: NSColor(red: 0.76, green: 0.74, blue: 0.70, alpha: 1))
if let arrow = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 22, weight: .light))
{
    let tinted = NSImage(size: arrow.size)
    tinted.lockFocus()
    NSColor(white: 0.48, alpha: 1).setFill()
    NSRect(origin: .zero, size: arrow.size).fill()
    arrow.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
    tinted.unlockFocus()
    tinted.draw(in: NSRect(x: 533.75, y: 400 - 210 - 14, width: 20, height: 28))
}

let instructionStyle = NSMutableParagraphStyle()
instructionStyle.alignment = .center
("Drag to Applications" as NSString).draw(
    in: NSRect(x: 437.5, y: 352, width: 212.5, height: 22),
    withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                     .foregroundColor: NSColor(white: 0.34, alpha: 1),
                     .paragraphStyle: instructionStyle]
)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("installer-branded@2x.png"))
