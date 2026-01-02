@testable import KeyPathAppKit
import XCTest

final class OverlayWindowFactoryTests: XCTestCase {
    func testWindowStyleForAccessibilityTestMode() {
        let style = OverlayWindowFactory.windowStyle(useAccessibilityTestMode: true)

        XCTAssertTrue(style.contains(.titled))
        XCTAssertTrue(style.contains(.resizable))
        XCTAssertTrue(style.contains(.closable))
        XCTAssertFalse(style.contains(.borderless))
    }

    func testWindowStyleForNormalMode() {
        let style = OverlayWindowFactory.windowStyle(useAccessibilityTestMode: false)

        XCTAssertTrue(style.contains(.borderless))
        XCTAssertTrue(style.contains(.resizable))
        XCTAssertFalse(style.contains(.titled))
    }

    func testDefaultOriginUsesBottomRightMargin() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let windowSize = CGSize(width: 200, height: 100)
        let origin = OverlayWindowFactory.defaultOrigin(
            visibleFrame: visibleFrame,
            windowSize: windowSize,
            margin: 20
        )

        XCTAssertEqual(origin.x, 780, accuracy: 0.001)
        XCTAssertEqual(origin.y, 20, accuracy: 0.001)
    }
}
