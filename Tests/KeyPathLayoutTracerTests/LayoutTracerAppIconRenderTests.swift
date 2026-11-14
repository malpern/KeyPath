import AppKit
@testable import KeyPathLayoutTracerKit
import XCTest

/// The tinted keyboard symbol colours only the glyph, not its whole rectangle.
final class LayoutTracerAppIconRenderTests: XCTestCase {
    func testSymbolTintDoesNotFillItsRectangle() throws {
        let icon = LayoutTracerAppIcon.makeIcon(size: 256)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(icon.tiffRepresentation)))
        if let path = ProcessInfo.processInfo.environment["KEYPATH_ICON_DUMP"] {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        // Count white pixels across the symbol's rectangle: a filled rect would be nearly all white.
        let width = rep.pixelsWide, height = rep.pixelsHigh
        var white = 0, total = 0
        for x in stride(from: Int(Double(width) * 0.14), to: Int(Double(width) * 0.68), by: 4) {
            for y in stride(from: Int(Double(height) * 0.42), to: Int(Double(height) * 0.80), by: 4) {
                total += 1
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   c.redComponent > 0.9, c.greenComponent > 0.9, c.blueComponent > 0.9 { white += 1 }
            }
        }
        XCTAssertGreaterThan(white, 0, "The glyph should be drawn")
        XCTAssertLessThan(Double(white) / Double(total), 0.8, "The tint should not fill the symbol's rectangle")
    }
}
