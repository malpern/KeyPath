@testable import KeyPathAppKit
import XCTest

final class OverlayInspectorPanelLayoutTests: XCTestCase {
    func testExpandedFrameKeepsOriginWhenNoOverflow() {
        let baseFrame = NSRect(x: 100, y: 50, width: 300, height: 200)
        let frame = InspectorPanelLayout.expandedFrame(
            baseFrame: baseFrame,
            inspectorWidth: 240,
            maxVisibleX: 1000
        )

        XCTAssertEqual(frame.origin.x, 100)
        XCTAssertEqual(frame.origin.y, 50)
        XCTAssertEqual(frame.size.width, 540)
        XCTAssertEqual(frame.size.height, 200)
    }

    func testExpandedFrameSlidesLeftOnOverflow() {
        let baseFrame = NSRect(x: 600, y: 20, width: 300, height: 180)
        let frame = InspectorPanelLayout.expandedFrame(
            baseFrame: baseFrame,
            inspectorWidth: 240,
            maxVisibleX: 1000
        )

        XCTAssertEqual(frame.origin.x, 360)
        XCTAssertEqual(frame.size.width, 540)
        XCTAssertEqual(frame.size.height, 180)
        XCTAssertEqual(frame.maxX, 1000)
    }

    func testCollapsedFrameReducesWidthByInspectorSize() {
        let expandedFrame = NSRect(x: 100, y: 50, width: 540, height: 200)
        let frame = InspectorPanelLayout.collapsedFrame(
            expandedFrame: expandedFrame,
            inspectorWidth: 240
        )

        XCTAssertEqual(frame.origin.x, 100)
        XCTAssertEqual(frame.size.width, 300)
        XCTAssertEqual(frame.size.height, 200)
    }
}
