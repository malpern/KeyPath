import HIDCaptureCore
import XCTest

final class CaptureLayoutTests: XCTestCase {
    func testRegularLayoutKeepsFullCaptureStage() {
        let layout = CaptureLayoutMetrics.resolve(width: 860, height: 660)
        XCTAssertEqual(layout.mode, .regular)
        XCTAssertEqual(layout.fieldHeight, 34)
        XCTAssertTrue(layout.showsFooter)
    }

    func testCompactLayoutPreservesCoreState() {
        let layout = CaptureLayoutMetrics.resolve(width: 620, height: 460)
        XCTAssertEqual(layout.mode, .compact)
        XCTAssertGreaterThan(layout.fieldHeight, 0)
    }

    func testTinyLayoutFitsMinimumWindow() {
        let layout = CaptureLayoutMetrics.resolve(width: 360, height: 250)
        XCTAssertEqual(layout.mode, .tiny)
        XCTAssertFalse(layout.showsFooter)
        XCTAssertLessThan(layout.padding, 18)
    }
}
