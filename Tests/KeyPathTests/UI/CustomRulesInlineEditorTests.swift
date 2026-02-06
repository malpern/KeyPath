@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class CustomRulesInlineEditorTests: XCTestCase {
    func testInlineRuleTrimsFieldsAndClearsEmptyNotes() {
        let rule = CustomRulesView.makeInlineRule(
            input: " a ",
            output: " b ",
            title: "  My Rule  ",
            notes: "   "
        )

        XCTAssertEqual(rule.input, "a")
        XCTAssertEqual(rule.output, "b")
        XCTAssertEqual(rule.title, "My Rule")
        XCTAssertNil(rule.notes)
    }

    func testInlineRuleAllowsSequenceOutput() {
        let rule = CustomRulesView.makeInlineRule(
            input: "a",
            output: "b c",
            title: "",
            notes: ""
        )

        let errors = CustomRuleValidator.validate(rule, existingRules: [])
        XCTAssertTrue(errors.isEmpty, "Sequence outputs should be valid for custom rules")
    }

    func testInlineRuleRejectsSequenceInput() {
        let rule = CustomRulesView.makeInlineRule(
            input: "a b",
            output: "c",
            title: "",
            notes: ""
        )

        let errors = CustomRuleValidator.validate(rule, existingRules: [])
        XCTAssertTrue(errors.contains { error in
            if case .invalidInputKey = error { return true }
            return false
        }, "Sequence inputs should be rejected for custom rules")
    }
}
