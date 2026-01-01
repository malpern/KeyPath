#!/usr/bin/env swift
import AppKit
import Foundation

/// Generates a template icon for the menu bar
/// - Simple 3D keycap design
/// - 18x18 (1x) and 36x36 (2x) sizes
/// - Set isTemplate=true when loading to enable automatic light/dark mode

func makeTemplateIcon(size: CGFloat, scale: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))

    let pixelSize = Int(size * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return img
    }
    NSGraphicsContext.current = context

    // Clear to transparent
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    // Draw a 3D keycap - outline style with inner cutout
    NSColor.black.setFill()
    NSColor.black.setStroke()

    // Keycap dimensions
    let padding: CGFloat = size * 0.08
    let capWidth = size - (padding * 2)
    let capHeight = size - (padding * 2)
    let capX = padding
    let capY = padding

    let cornerRadius: CGFloat = size * 0.18

    // Create outer path
    let outerRect = NSRect(x: capX, y: capY, width: capWidth, height: capHeight)
    let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Inner top surface (inset to create depth/3D effect)
    let inset: CGFloat = size * 0.14
    let topOffset: CGFloat = size * 0.06
    let innerRect = NSRect(
        x: capX + inset,
        y: capY + inset + topOffset,
        width: capWidth - (inset * 2),
        height: capHeight - (inset * 2) - topOffset
    )
    let innerCorner = cornerRadius * 0.6
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: innerCorner, yRadius: innerCorner)

    // Create compound path: outer minus inner (creates frame effect)
    outerPath.append(innerPath.reversed)
    outerPath.fill()

    NSGraphicsContext.restoreGraphicsState()
    img.addRepresentation(rep)
    return img
}

func writePNG(_ image: NSImage, to url: URL) throws {
    // Get the bitmap representation directly to preserve alpha
    guard let rep = image.representations.first as? NSBitmapImageRep,
          let data = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
    }
    try data.write(to: url)
}

let fm = FileManager.default

// Paths relative to script location
let scriptDir = URL(fileURLWithPath: fm.currentDirectoryPath)
let rootDir = scriptDir.deletingLastPathComponent().deletingLastPathComponent()
let resourcesDir = rootDir.appendingPathComponent("Sources/KeyPathApp/Resources", isDirectory: true)

// Create directory if needed
try? fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

// Generate 1x (18x18) and 2x (36x36) versions
// Menu bar icons should be 18pt (standard height)
let icon1x = makeTemplateIcon(size: 18, scale: 1)
let icon2x = makeTemplateIcon(size: 18, scale: 2)

let url1x = resourcesDir.appendingPathComponent("menubar-icon.png")
let url2x = resourcesDir.appendingPathComponent("menubar-icon@2x.png")

try writePNG(icon1x, to: url1x)
try writePNG(icon2x, to: url2x)

print("Generated menu bar template icons:")
print("  1x: \(url1x.path)")
print("  2x: \(url2x.path)")
print("")
print("Usage in code:")
print("  if let image = NSImage(named: \"menubar-icon\") {")
print("      image.isTemplate = true")
print("      statusItem.button?.image = image")
print("  }")
