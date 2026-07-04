@testable import KeyPathAppKit
import SwiftUI
import XCTest

/// Regression tests for GitHub issue #806: the HRM Pack Detail hold-timing
/// slider exposed accessibility Increment/Decrement actions, but invoking
/// them did not change the exposed value because the Slider only had a
/// custom (inverted) `Binding` and a manually-overridden `accessibilityValue`
/// string — nothing wired the AX adjustable action to actually mutate the
/// bound value. `HoldTimingSliderRow.adjustedValue` is the pure function
/// backing `.accessibilityAdjustableAction`; tested directly here since it
/// doesn't require driving SwiftUI's accessibility runtime.
final class HoldTimingSliderRowTests: XCTestCase {
    private let range: ClosedRange<Double> = 120 ... 300
    private let step: Double = 20

    func testIncrementMovesDisplayedThumbTowardPreferModifiers() {
        // Displayed (inverted) position for value=180 is 120+300-180=240.
        // Incrementing should move the *displayed* position up by `step`,
        // which corresponds to a smaller raw value.
        let newValue = HoldTimingSliderRow.adjustedValue(
            current: 180, direction: .increment, range: range, step: step
        )
        XCTAssertEqual(newValue, 160)
    }

    func testDecrementMovesDisplayedThumbTowardPreferLetters() {
        let newValue = HoldTimingSliderRow.adjustedValue(
            current: 180, direction: .decrement, range: range, step: step
        )
        XCTAssertEqual(newValue, 200)
    }

    func testIncrementClampsAtRangeBoundary() {
        // Raw value 120 is already the max displayed position; incrementing
        // further must clamp rather than exceed the range.
        let newValue = HoldTimingSliderRow.adjustedValue(
            current: 120, direction: .increment, range: range, step: step
        )
        XCTAssertEqual(newValue, 120)
    }

    func testDecrementClampsAtRangeBoundary() {
        let newValue = HoldTimingSliderRow.adjustedValue(
            current: 300, direction: .decrement, range: range, step: step
        )
        XCTAssertEqual(newValue, 300)
    }

    func testRepeatedIncrementsWalkTheFullRange() {
        var value = 300.0
        for _ in 0 ..< 9 {
            value = HoldTimingSliderRow.adjustedValue(
                current: value, direction: .increment, range: range, step: step
            )
        }
        XCTAssertEqual(value, 120, "9 increments of 20 across a 180ms range should reach the far end")
    }
}
