import AppKit
import Foundation

struct IconSpec {
    let size: CGFloat
    let scale: CGFloat
}

let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]

let overlayPath = CommandLine.arguments.dropFirst().first // optional path to overlay PNG
let overlayImage: NSImage? = {
    if let path = overlayPath {
        return NSImage(contentsOfFile: path)
    }
    return nil
}()

func makeIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    defer { img.unlockFocus() }

    // Rounded rect background with solid system blue (match main UI)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18)
    NSColor.systemBlue.setFill()
    path.fill()

    // Draw overlay if provided; otherwise draw SF Symbol keyboard
    if let overlay = overlayImage {
        let inset: CGFloat = size * 0.14
        let overlayRect = rect.insetBy(dx: inset, dy: inset)
        overlay.draw(in: overlayRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
    } else {
        if let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) {
            let scale: CGFloat = 0.52
            let symbolSize = NSSize(width: size * scale, height: size * scale)
            let symbolOrigin = NSPoint(x: (size - symbolSize.width) / 2, y: (size - symbolSize.height) / 2)
            let symbolRect = NSRect(origin: symbolOrigin, size: symbolSize)
            let config = NSImage.SymbolConfiguration(pointSize: symbolSize.height, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
            let tinted = symbol.withSymbolConfiguration(config)
            tinted?.draw(in: symbolRect)
        }
    }
    return img
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
    }
    try data.write(to: url)
}

let fm = FileManager.default
let outDir = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? fm.removeItem(at: outDir)
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

for s in sizes {
    let img = makeIcon(size: s)
    let url = outDir.appendingPathComponent("icon_\(Int(s))x\(Int(s)).png")
    try writePNG(img, to: url)
}

print("✅ Generated icon PNGs at \(outDir.path)")

