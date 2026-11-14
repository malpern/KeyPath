import AppKit
@testable import KeyPathAppKit
import XCTest

/// The normalised favicon fills its whole 2x bitmap, not one quadrant.
final class FaviconNormalizationTests: XCTestCase {
    func testNormalizedIconFillsTheBitmap() async throws {
        let source = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let normalized = await MainActor.run { FaviconFetcher.shared.normalizedFaviconImage(source) }
        let bitmap = try XCTUnwrap(normalized.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(bitmap.pixelsWide, 128)
        XCTAssertEqual(normalized.size, NSSize(width: 64, height: 64))
        // Corners in every quadrant are painted.
        for (x, y) in [(2, 2), (125, 2), (2, 125), (125, 125)] {
            let alpha = try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent
            XCTAssertGreaterThan(alpha, 0.9, "pixel (\(x), \(y)) is empty")
        }
    }
}
