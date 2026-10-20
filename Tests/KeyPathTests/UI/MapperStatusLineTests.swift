import AppKit
@testable import KeyPathAppKit
import SwiftUI
import XCTest

/// The overlay Mapper saves on capture with no Save button, so its status line
/// is the only place a declined save is visible. These render it for real.
@MainActor
final class MapperStatusLineTests: XCTestCase {
    private func host(_ message: String?, isError: Bool) -> NSHostingView<some View> {
        let hosted = NSHostingView(rootView: MapperStatusLine(message: message, isError: isError).frame(width: 300))
        hosted.frame = CGRect(x: 0, y: 0, width: 300, height: 120)
        hosted.layoutSubtreeIfNeeded()
        return hosted
    }

    /// Distinct colours drawn by the hosted view: a blank render has one.
    private func distinctColours(in view: NSView) throws -> Set<UInt32> {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        var seen = Set<UInt32>()
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                if let colour = rep.colorAt(x: x, y: y) {
                    let r = UInt32(colour.redComponent * 255), g = UInt32(colour.greenComponent * 255), b = UInt32(colour.blueComponent * 255)
                    seen.insert(r << 16 | g << 8 | b)
                }
            }
        }
        return seen
    }

    func testAMessageTakesSpaceAndDrawsText() throws {
        let hosted = host("Louder sends Volume Up, which the current backend can't send.", isError: true)
        XCTAssertGreaterThan(hosted.fittingSize.height, 0, "a status takes space")
        XCTAssertGreaterThan(try distinctColours(in: hosted).count, 1, "a status draws glyphs, not a blank")
    }

    func testAnErrorIsDrawnInRed() throws {
        let error = try distinctColours(in: host("Refused", isError: true))
        let plain = try distinctColours(in: host("Refused", isError: false))
        let reddish = error.filter { ($0 >> 16) & 0xFF > 150 && ($0 >> 8) & 0xFF < 110 && $0 & 0xFF < 110 }
        XCTAssertFalse(reddish.isEmpty, "an error status draws in red")
        XCTAssertNotEqual(error, plain)
    }

    func testNoMessageRendersNothing() {
        let hosted = host(nil, isError: false)
        XCTAssertEqual(hosted.fittingSize.height, 0)
    }
}
