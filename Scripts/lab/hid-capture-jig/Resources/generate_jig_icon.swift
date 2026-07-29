import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_jig_icon.swift OUTPUT.iconset\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

struct IconVariant {
    let points: Int
    let scale: Int

    var filename: String {
        scale == 1
            ? "icon_\(points)x\(points).png"
            : "icon_\(points)x\(points)@\(scale)x.png"
    }
}

let variants = [
    IconVariant(points: 16, scale: 1),
    IconVariant(points: 16, scale: 2),
    IconVariant(points: 32, scale: 1),
    IconVariant(points: 32, scale: 2),
    IconVariant(points: 128, scale: 1),
    IconVariant(points: 128, scale: 2),
    IconVariant(points: 256, scale: 1),
    IconVariant(points: 256, scale: 2),
    IconVariant(points: 512, scale: 1),
    IconVariant(points: 512, scale: 2),
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil,
                 lineWidth: CGFloat = 1)
{
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let tile = canvas.insetBy(dx: size * 0.045, dy: size * 0.045)
    let tilePath = NSBezierPath(
        roundedRect: tile,
        xRadius: size * 0.205,
        yRadius: size * 0.205
    )
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
    shadow.shadowBlurRadius = size * 0.055
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.025)
    shadow.set()
    color(0.035, 0.075, 0.095).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let background = NSGradient(colors: [
        color(0.16, 0.28, 0.32),
        color(0.025, 0.07, 0.09),
    ])!
    background.draw(in: tilePath, angle: -72)
    color(0.42, 0.60, 0.62, 0.45).setStroke()
    tilePath.lineWidth = max(1, size * 0.009)
    tilePath.stroke()

    // Machined base plate and its four registration bolts.
    let plate = NSRect(
        x: size * 0.17, y: size * 0.20,
        width: size * 0.66, height: size * 0.49
    )
    roundedRect(
        plate,
        radius: size * 0.075,
        fill: color(0.60, 0.70, 0.70),
        stroke: color(0.84, 0.91, 0.89, 0.78),
        lineWidth: size * 0.012
    )
    let insetPlate = plate.insetBy(dx: size * 0.035, dy: size * 0.035)
    roundedRect(
        insetPlate,
        radius: size * 0.055,
        fill: color(0.10, 0.18, 0.20),
        stroke: color(0.03, 0.07, 0.08),
        lineWidth: size * 0.008
    )
    for point in [
        NSPoint(x: plate.minX + size * 0.055, y: plate.minY + size * 0.055),
        NSPoint(x: plate.maxX - size * 0.055, y: plate.minY + size * 0.055),
        NSPoint(x: plate.minX + size * 0.055, y: plate.maxY - size * 0.055),
        NSPoint(x: plate.maxX - size * 0.055, y: plate.maxY - size * 0.055),
    ] {
        let bolt = NSRect(
            x: point.x - size * 0.018, y: point.y - size * 0.018,
            width: size * 0.036, height: size * 0.036
        )
        color(0.82, 0.91, 0.89).setFill()
        NSBezierPath(ovalIn: bolt).fill()
    }

    // Opposing clamp jaws make this read as a fixture instead of a keyboard app.
    let jawColor = color(0.76, 0.84, 0.82)
    let jawEdge = color(0.38, 0.52, 0.53)
    let leftPost = NSRect(x: size * 0.22, y: size * 0.31, width: size * 0.13, height: size * 0.27)
    let rightPost = NSRect(x: size * 0.65, y: size * 0.31, width: size * 0.13, height: size * 0.27)
    roundedRect(leftPost, radius: size * 0.035, fill: jawColor, stroke: jawEdge, lineWidth: size * 0.01)
    roundedRect(rightPost, radius: size * 0.035, fill: jawColor, stroke: jawEdge, lineWidth: size * 0.01)
    roundedRect(
        NSRect(x: size * 0.29, y: size * 0.39, width: size * 0.14, height: size * 0.10),
        radius: size * 0.025, fill: jawColor, stroke: jawEdge, lineWidth: size * 0.008
    )
    roundedRect(
        NSRect(x: size * 0.57, y: size * 0.39, width: size * 0.14, height: size * 0.10),
        radius: size * 0.025, fill: jawColor, stroke: jawEdge, lineWidth: size * 0.008
    )

    // The amber test key is intentionally generic: it is not the KeyPath product mark.
    let keyBase = NSRect(x: size * 0.37, y: size * 0.31, width: size * 0.26, height: size * 0.27)
    roundedRect(
        keyBase,
        radius: size * 0.055,
        fill: color(0.88, 0.29, 0.055),
        stroke: color(1.0, 0.62, 0.13),
        lineWidth: size * 0.012
    )
    let keyFace = NSRect(x: size * 0.395, y: size * 0.365, width: size * 0.21, height: size * 0.16)
    roundedRect(
        keyFace,
        radius: size * 0.038,
        fill: color(1.0, 0.88, 0.58),
        stroke: color(1.0, 0.67, 0.19),
        lineWidth: size * 0.008
    )

    // A measurement probe completes the test-jig metaphor.
    let probe = NSBezierPath()
    probe.move(to: NSPoint(x: size * 0.50, y: size * 0.81))
    probe.line(to: NSPoint(x: size * 0.50, y: size * 0.61))
    color(0.86, 0.95, 0.92).setStroke()
    probe.lineWidth = max(1.5, size * 0.026)
    probe.lineCapStyle = .round
    probe.stroke()
    let collar = NSRect(x: size * 0.43, y: size * 0.72, width: size * 0.14, height: size * 0.09)
    roundedRect(collar, radius: size * 0.025, fill: jawColor, stroke: jawEdge, lineWidth: size * 0.009)
    let probeTip = NSRect(x: size * 0.475, y: size * 0.575, width: size * 0.05, height: size * 0.05)
    color(0.34, 0.88, 0.70).setFill()
    NSBezierPath(ovalIn: probeTip).fill()

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(
            domain: "KeyPathJigIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"]
        )
    }
    try data.write(to: url, options: .atomic)
}

for variant in variants {
    let pixels = CGFloat(variant.points * variant.scale)
    try writePNG(render(size: pixels), to: outputDirectory.appendingPathComponent(variant.filename))
}
