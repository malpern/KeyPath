import Foundation
@testable import KeyPathAppKit
import XCTest

final class ChordPressWindowCopyTests: XCTestCase {
    func testExplanationDefinesStartCompletionAndFallback() {
        let explanation = String(localized: ChordPressWindowCopy.explanation)

        XCTAssertTrue(explanation.contains("press the first chord key"))
        XCTAssertTrue(explanation.contains("last required key"))
        XCTAssertTrue(explanation.contains("expires"))
        XCTAssertTrue(explanation.contains("normal layer actions"))
    }

    func testTradeoffExplainsLowerAndHigherValuesInFeltTerms() {
        let tradeoff = String(localized: ChordPressWindowCopy.tradeoff)

        XCTAssertTrue(tradeoff.contains("Lower values"))
        XCTAssertTrue(tradeoff.contains("respond sooner"))
        XCTAssertTrue(tradeoff.contains("more precise"))
        XCTAssertTrue(tradeoff.contains("Higher values"))
        XCTAssertTrue(tradeoff.contains("easier"))
        XCTAssertTrue(tradeoff.contains("delay"))
    }

    func testAccessibilityValueIncludesTimingPresetAndTradeoff() {
        let value = ChordPressWindowCopy.accessibilityValue(milliseconds: 250, speed: .fast)

        XCTAssertTrue(value.contains("250 milliseconds"))
        XCTAssertTrue(value.contains("Fast"))
        XCTAssertTrue(value.contains("faster fallback"))
        XCTAssertTrue(value.contains("easier chord"))
    }
}
