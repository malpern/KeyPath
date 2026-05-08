@testable import KeyPathAppKit
import XCTest

final class OverlayInspectorMathTests: XCTestCase {
    func testEasedProgressClampsEndpoints() {
        XCTAssertEqual(OverlayInspectorMath.easedProgress(0), 0, accuracy: 0.0001)
        XCTAssertEqual(OverlayInspectorMath.easedProgress(1), 1, accuracy: 0.0001)
    }

    func testRevealValueHitsTargetAtDuration() {
        let value = OverlayInspectorMath.revealValue(
            start: 0,
            target: 1,
            elapsed: 1.0,
            duration: 1.0
        )

        XCTAssertEqual(value, 1, accuracy: 0.0001)
    }

    func testRevealValueWithZeroDurationReturnsTarget() {
        let value = OverlayInspectorMath.revealValue(
            start: 0.25,
            target: 0.75,
            elapsed: 0.1,
            duration: 0
        )

        XCTAssertEqual(value, 0.75, accuracy: 0.0001)
    }

    func testClampedRevealClampsToBounds() {
        XCTAssertEqual(
            OverlayInspectorMath.clampedReveal(expandedWidth: 100, collapsedWidth: 120, inspectorWidth: 40),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            OverlayInspectorMath.clampedReveal(expandedWidth: 200, collapsedWidth: 100, inspectorWidth: 40),
            1,
            accuracy: 0.0001
        )
    }
}
