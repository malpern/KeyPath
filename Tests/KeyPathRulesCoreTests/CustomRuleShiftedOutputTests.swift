@testable import KeyPathRulesCore
@preconcurrency import XCTest

final class CustomRuleShiftedOutputTests: XCTestCase {
    func testAsKeyMappingIncludesShiftedOutput() {
        let rule = CustomRule(input: "g", action: .keystroke(key: "M-up"), shiftedOutput: "M-down")

        let mapping = rule.asKeyMapping()

        XCTAssertEqual(mapping.input, "g")
        XCTAssertEqual(mapping.action, .keystroke(key: "M-up"))
        XCTAssertEqual(mapping.shiftedOutput, "M-down")
    }

    func testCodableRoundTripPreservesShiftedOutput() throws {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 1000)
        let original = CustomRule(
            id: UUID(),
            title: "Go to top/bottom",
            input: "g",
            action: .keystroke(key: "M-up"),
            shiftedOutput: "M-down",
            isEnabled: true,
            notes: "Vim-style",
            createdAt: fixedDate
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomRule.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.shiftedOutput, "M-down")
    }

    func testDecodeLegacyJSONWithoutShiftedOutputDefaultsToNil() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title": "",
          "input": "g",
          "action": {"keystroke":{"key":"M-up"}},
          "isEnabled": true,
          "createdAt": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CustomRule.self, from: json)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.input, "g")
        XCTAssertEqual(decoded.action, .keystroke(key: "M-up"))
        XCTAssertNil(decoded.shiftedOutput)
        XCTAssertEqual(decoded.targetLayer, .base)
    }
}
