@testable import KeyPathAppKit
import SwiftUI
import XCTest

/// Guards the `FloatingKeymapLabel` Equatable contract (#485): every display
/// input must participate in `==`, so `.equatable()` never skips a re-render that
/// a changed input requires (which would leave a label visually stale).
@MainActor
final class FloatingKeymapLabelEquatableTests: XCTestCase {
    private func makeLabel(
        label: String = "a",
        targetFrame: CGRect = CGRect(x: 0, y: 0, width: 10, height: 10),
        isVisible: Bool = true,
        scale: CGFloat = 1,
        enableAnimation: Bool = false,
        animateVisibility: Bool = true,
        fadeAmount: CGFloat = 0,
        isDarkMode: Bool = false,
        shiftSymbolOverride: String? = nil
    ) -> FloatingKeymapLabel {
        FloatingKeymapLabel(
            label: label,
            targetFrame: targetFrame,
            isVisible: isVisible,
            scale: scale,
            colorway: .default,
            enableAnimation: enableAnimation,
            animateVisibility: animateVisibility,
            fadeAmount: fadeAmount,
            isDarkMode: isDarkMode,
            shiftSymbolOverride: shiftSymbolOverride
        )
    }

    func testEqualWhenAllInputsMatch() {
        XCTAssertEqual(makeLabel(), makeLabel())
    }

    func testEachDisplayInputBreaksEquality() {
        let base = makeLabel()
        XCTAssertNotEqual(base, makeLabel(label: "b"))
        XCTAssertNotEqual(base, makeLabel(targetFrame: CGRect(x: 1, y: 0, width: 10, height: 10)))
        XCTAssertNotEqual(base, makeLabel(isVisible: false))
        XCTAssertNotEqual(base, makeLabel(scale: 2))
        XCTAssertNotEqual(base, makeLabel(enableAnimation: true))
        XCTAssertNotEqual(base, makeLabel(animateVisibility: false))
        XCTAssertNotEqual(base, makeLabel(fadeAmount: 0.5))
        XCTAssertNotEqual(base, makeLabel(isDarkMode: true))
        XCTAssertNotEqual(base, makeLabel(shiftSymbolOverride: "!"))
    }
}
