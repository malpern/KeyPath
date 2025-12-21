@testable import KeyPathAppKit
import XCTest

final class OverlayInspectorPanelLayoutTests: XCTestCase {
    func testTargetFrameUsesFullWidthWhenSpaceAvailable() {
        let overlayFrame = NSRect(x: 100, y: 50, width: 300, height: 200)
        let frame = InspectorPanelLayout.targetFrame(
            overlayFrame: overlayFrame,
            maxVisibleX: 900,
            panelWidth: 240
        )

        XCTAssertEqual(frame.origin.x, 400)
        XCTAssertEqual(frame.origin.y, 50)
        XCTAssertEqual(frame.size.width, 240)
        XCTAssertEqual(frame.size.height, 200)
    }

    func testTargetFrameClampsWidthWhenSpaceIsLimited() {
        let overlayFrame = NSRect(x: 600, y: 20, width: 300, height: 180)
        let frame = InspectorPanelLayout.targetFrame(
            overlayFrame: overlayFrame,
            maxVisibleX: 1000,
            panelWidth: 240
        )

        XCTAssertEqual(frame.origin.x, 900)
        XCTAssertEqual(frame.size.width, 100)
        XCTAssertEqual(frame.size.height, 180)
    }

    func testTargetFrameZeroWidthWhenNoSpace() {
        let overlayFrame = NSRect(x: 700, y: 20, width: 300, height: 180)
        let frame = InspectorPanelLayout.targetFrame(
            overlayFrame: overlayFrame,
            maxVisibleX: 1000,
            panelWidth: 240
        )

        XCTAssertEqual(frame.size.width, 0)
    }

    func testCollapsedFrameIsOnePointWide() {
        let overlayFrame = NSRect(x: 100, y: 50, width: 300, height: 200)
        let frame = InspectorPanelLayout.collapsedFrame(overlayFrame: overlayFrame)

        XCTAssertEqual(frame.origin.x, 400)
        XCTAssertEqual(frame.size.width, 1)
        XCTAssertEqual(frame.size.height, 200)
    }
}
