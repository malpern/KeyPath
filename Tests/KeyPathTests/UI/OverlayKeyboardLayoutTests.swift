@testable import KeyPathAppKit
import XCTest

final class OverlayKeyboardLayoutTests: XCTestCase {
    func testEscLeftInsetMatchesKeyGapAtScaleOne() {
        let inset = OverlayKeyboardView.escLeftInset(
            for: .macBookUS,
            scale: 1,
            keyUnitSize: 32,
            keyGap: 2
        )

        XCTAssertEqual(inset, 2, accuracy: 0.001)
    }
}
