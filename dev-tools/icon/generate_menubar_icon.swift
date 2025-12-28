#!/usr/bin/env swift
import AppKit
import Foundation

/// Generates a template icon for the menu bar
/// - Black keyboard shape on transparent background
/// - 18x18 (1x) and 36x36 (2x) sizes
/// - Set isTemplate=true when loading to enable automatic light/dark mode

func makeTemplateIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    defer { img.unlockFocus() }

    // Draw SF Symbol keyboard in black
    if let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) {
        // Use hierarchical rendering for better visual weight
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.85, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.black]))
        if let tinted = symbol.withSymbolConfiguration(config) {
            // Center the symbol
            let symbolRect = NSRect(x: 0, y: 0, width: size, height: size)
            tinted.draw(in: symbolRect)
        }
    }

    return img
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
    }
    try data.write(to: url)
}

let fm = FileManager.default

// Output to KeyPathApp Resources
let resourcesDir = URL(fileURLWithPath: fm.currentDirectoryPath)
    .deletingLastPathComponent() // dev-tools
    .deletingLastPathComponent() // KeyPath root
    .appendingPathComponent("Sources/KeyPathApp/Resources", isDirectory: true)

// Create directory if needed
try? fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

// Generate 1x (18x18) and 2x (36x36) versions
let icon1x = makeTemplateIcon(size: 18)
let icon2x = makeTemplateIcon(size: 36)

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
