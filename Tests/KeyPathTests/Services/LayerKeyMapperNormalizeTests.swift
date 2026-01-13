@testable import KeyPathAppKit
import XCTest

final class LayerKeyMapperNormalizeTests: XCTestCase {
    func testNormalizeKeyNameHandlesSimulatorGlyphs() {
        let cases: [(input: String, expected: String)] = [
            ("␠", "space"),
            ("␣", "space"),
            ("⏎", "enter"),
            ("␈", "backspace"),
            ("⭾", "tab"),
            ("−", "minus")
        ]

        for testCase in cases {
            XCTAssertEqual(
                LayerKeyMapper.normalizeKeyName(testCase.input),
                testCase.expected,
                "Expected '\(testCase.input)' to normalize to '\(testCase.expected)'"
            )
        }
    }
}
