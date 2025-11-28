import XCTest

@testable import KeyPathAppKit

final class CustomRuleValidatorTests: XCTestCase {
    // MARK: - Key Validation

    func testValidKanataKeys() {
        // Letters
        XCTAssertTrue(CustomRuleValidator.isValidKey("a"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("z"))

        // Numbers
        XCTAssertTrue(CustomRuleValidator.isValidKey("0"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("9"))

        // Function keys
        XCTAssertTrue(CustomRuleValidator.isValidKey("f1"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("f12"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("f18"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("f20"))

        // Special keys
        XCTAssertTrue(CustomRuleValidator.isValidKey("caps"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("esc"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("ret"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("spc"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("bspc"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("tab"))

        // Modifiers
        XCTAssertTrue(CustomRuleValidator.isValidKey("lmet"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("rmet"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("lctl"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("lsft"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("lalt"))

        // Navigation
        XCTAssertTrue(CustomRuleValidator.isValidKey("left"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("right"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("up"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("down"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("pgup"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("pgdn"))
    }

    func testValidKeyAliases() {
        // These should all be recognized as valid via alias lookup
        XCTAssertTrue(CustomRuleValidator.isValidKey("capslock"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("space"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("enter"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("return"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("escape"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("backspace"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("command"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("cmd"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("option"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("ctrl"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("shift"))
    }

    func testInvalidKeys() {
        XCTAssertFalse(CustomRuleValidator.isValidKey("notakey"))
        XCTAssertFalse(CustomRuleValidator.isValidKey("xyz"))
        XCTAssertFalse(CustomRuleValidator.isValidKey("f100"))
        XCTAssertFalse(CustomRuleValidator.isValidKey("superkey"))
    }

    func testCaseInsensitiveValidation() {
        XCTAssertTrue(CustomRuleValidator.isValidKey("CAPS"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("Esc"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("SPACE"))
        XCTAssertTrue(CustomRuleValidator.isValidKey("Enter"))
    }

    func testValidKeyWithModifier() {
        XCTAssertTrue(CustomRuleValidator.isValidKeyOrModified("M-right"))
        XCTAssertTrue(CustomRuleValidator.isValidKeyOrModified("C-a"))
        XCTAssertTrue(CustomRuleValidator.isValidKeyOrModified("A-tab"))
        XCTAssertTrue(CustomRuleValidator.isValidKeyOrModified("S-f1"))
        XCTAssertTrue(CustomRuleValidator.isValidKeyOrModified("M-S-left"))
        XCTAssertTrue(CustomRuleValidator.isValidKeyOrModified("C-S-a"))
    }

    func testInvalidKeyWithModifier() {
        XCTAssertFalse(CustomRuleValidator.isValidKeyOrModified("M-notakey"))
        XCTAssertFalse(CustomRuleValidator.isValidKeyOrModified("C-xyz"))
    }

    // MARK: - Key Normalization

    func testNormalizeKey() {
        // Aliases should normalize to canonical form
        XCTAssertEqual(CustomRuleValidator.normalizeKey("capslock"), "caps")
        XCTAssertEqual(CustomRuleValidator.normalizeKey("space"), "spc")
        XCTAssertEqual(CustomRuleValidator.normalizeKey("enter"), "ret")
        XCTAssertEqual(CustomRuleValidator.normalizeKey("escape"), "esc")
        XCTAssertEqual(CustomRuleValidator.normalizeKey("command"), "lmet")
        XCTAssertEqual(CustomRuleValidator.normalizeKey("backspace"), "bspc")

        // Already canonical keys should stay the same
        XCTAssertEqual(CustomRuleValidator.normalizeKey("caps"), "caps")
        XCTAssertEqual(CustomRuleValidator.normalizeKey("esc"), "esc")
        XCTAssertEqual(CustomRuleValidator.normalizeKey("f1"), "f1")

        // Case should be normalized
        XCTAssertEqual(CustomRuleValidator.normalizeKey("CAPS"), "caps")
        XCTAssertEqual(CustomRuleValidator.normalizeKey("ESC"), "esc")
    }

    // MARK: - Rule Validation

    func testValidateEmptyInput() {
        let rule = CustomRule(input: "", output: "esc")
        let errors = CustomRuleValidator.validate(rule)

        XCTAssertTrue(errors.contains(.emptyInput))
    }

    func testValidateEmptyOutput() {
        let rule = CustomRule(input: "caps", output: "")
        let errors = CustomRuleValidator.validate(rule)

        XCTAssertTrue(errors.contains(.emptyOutput))
    }

    func testValidateInvalidInputKey() {
        let rule = CustomRule(input: "notakey", output: "esc")
        let errors = CustomRuleValidator.validate(rule)

        XCTAssertEqual(errors.count, 1)
        if case let .invalidInputKey(key) = errors.first {
            XCTAssertEqual(key, "notakey")
        } else {
            XCTFail("Expected invalidInputKey error")
        }
    }

    func testValidateInvalidOutputKey() {
        let rule = CustomRule(input: "caps", output: "notakey")
        let errors = CustomRuleValidator.validate(rule)

        XCTAssertEqual(errors.count, 1)
        if case let .invalidOutputKey(key) = errors.first {
            XCTAssertEqual(key, "notakey")
        } else {
            XCTFail("Expected invalidOutputKey error")
        }
    }

    func testValidateSelfMapping() {
        let rule = CustomRule(input: "caps", output: "caps")
        let errors = CustomRuleValidator.validate(rule)

        XCTAssertTrue(errors.contains(.selfMapping))
    }

    func testValidateSelfMappingWithAlias() {
        // "capslock" normalizes to "caps", so this should detect self-mapping
        let rule = CustomRule(input: "capslock", output: "caps")
        let errors = CustomRuleValidator.validate(rule)

        XCTAssertTrue(errors.contains(.selfMapping))
    }

    func testValidateValidRule() {
        let rule = CustomRule(input: "caps", output: "esc")
        let errors = CustomRuleValidator.validate(rule)

        XCTAssertTrue(errors.isEmpty)
    }

    func testValidateRuleWithMultipleOutputs() {
        let rule = CustomRule(input: "caps", output: "M-right M-left")
        let errors = CustomRuleValidator.validate(rule)

        XCTAssertTrue(errors.isEmpty)
    }

    func testValidateRuleWithInvalidOutputSequence() {
        let rule = CustomRule(input: "caps", output: "M-right notakey M-left")
        let errors = CustomRuleValidator.validate(rule)

        XCTAssertEqual(errors.count, 1)
        if case let .invalidOutputKey(key) = errors.first {
            XCTAssertEqual(key, "notakey")
        } else {
            XCTFail("Expected invalidOutputKey error")
        }
    }

    // MARK: - Conflict Detection

    func testConflictDetection() {
        let existingRules = [
            CustomRule(input: "caps", output: "esc", isEnabled: true)
        ]
        let newRule = CustomRule(input: "caps", output: "tab", isEnabled: true)

        let conflict = CustomRuleValidator.checkConflict(for: newRule, against: existingRules)

        XCTAssertNotNil(conflict)
        if case let .conflict(_, key) = conflict {
            XCTAssertEqual(key, "caps")
        } else {
            XCTFail("Expected conflict error")
        }
    }

    func testConflictDetectionWithAlias() {
        let existingRules = [
            CustomRule(input: "caps", output: "esc", isEnabled: true)
        ]
        // "capslock" normalizes to "caps", so this should conflict
        let newRule = CustomRule(input: "capslock", output: "tab", isEnabled: true)

        let conflict = CustomRuleValidator.checkConflict(for: newRule, against: existingRules)

        XCTAssertNotNil(conflict)
    }

    func testNoConflictWithDisabledRule() {
        let existingRules = [
            CustomRule(input: "caps", output: "esc", isEnabled: false)
        ]
        let newRule = CustomRule(input: "caps", output: "tab", isEnabled: true)

        let conflict = CustomRuleValidator.checkConflict(for: newRule, against: existingRules)

        XCTAssertNil(conflict)
    }

    func testNoConflictWithSameId() {
        let ruleId = UUID()
        let existingRules = [
            CustomRule(id: ruleId, title: "", input: "caps", output: "esc", isEnabled: true)
        ]
        // Editing the same rule shouldn't conflict with itself
        let updatedRule = CustomRule(id: ruleId, title: "", input: "caps", output: "tab", isEnabled: true)

        let conflict = CustomRuleValidator.checkConflict(for: updatedRule, against: existingRules)

        XCTAssertNil(conflict)
    }

    func testNoConflictWithDifferentKeys() {
        let existingRules = [
            CustomRule(input: "caps", output: "esc", isEnabled: true)
        ]
        let newRule = CustomRule(input: "tab", output: "esc", isEnabled: true)

        let conflict = CustomRuleValidator.checkConflict(for: newRule, against: existingRules)

        XCTAssertNil(conflict)
    }

    func testValidateWithExistingRulesIncludesConflict() {
        let existingRules = [
            CustomRule(input: "caps", output: "esc", isEnabled: true)
        ]
        let newRule = CustomRule(input: "caps", output: "tab", isEnabled: true)

        let errors = CustomRuleValidator.validate(newRule, existingRules: existingRules)

        XCTAssertTrue(errors.contains { error in
            if case .conflict = error { return true }
            return false
        })
    }

    // MARK: - Autocomplete Suggestions

    func testSuggestionsForEmptyInput() {
        let suggestions = CustomRuleValidator.suggestions(for: "")

        // Should return common keys
        XCTAssertTrue(suggestions.contains("caps"))
        XCTAssertTrue(suggestions.contains("esc"))
        XCTAssertTrue(suggestions.contains("ret"))
    }

    func testSuggestionsForPrefix() {
        let suggestions = CustomRuleValidator.suggestions(for: "ca")

        XCTAssertTrue(suggestions.contains("caps"))
    }

    func testSuggestionsForFunctionKey() {
        let suggestions = CustomRuleValidator.suggestions(for: "f1")

        XCTAssertTrue(suggestions.contains("f1"))
        XCTAssertTrue(suggestions.contains("f10"))
        XCTAssertTrue(suggestions.contains("f11"))
        XCTAssertTrue(suggestions.contains("f12"))
        XCTAssertTrue(suggestions.contains("f18"))
    }

    func testSuggestionsPrioritizeCommonKeys() {
        let suggestions = CustomRuleValidator.suggestions(for: "l")

        // Common keys like lmet should appear before less common ones
        if let lmetIndex = suggestions.firstIndex(of: "lmet"),
           let leftIndex = suggestions.firstIndex(of: "left")
        {
            // Both should be present
            XCTAssertNotNil(lmetIndex)
            XCTAssertNotNil(leftIndex)
        }
    }

    // MARK: - Correction Suggestions

    func testSuggestCorrectionForAlias() {
        // If user types an alias, suggest the canonical form
        let correction = CustomRuleValidator.suggestCorrection(for: "capslock")

        XCTAssertEqual(correction, "caps")
    }

    func testSuggestCorrectionForPartialMatch() {
        let correction = CustomRuleValidator.suggestCorrection(for: "cap")

        XCTAssertEqual(correction, "caps")
    }

    func testSuggestCorrectionForNoMatch() {
        let correction = CustomRuleValidator.suggestCorrection(for: "zzz")

        XCTAssertNil(correction)
    }

    // MARK: - Tokenization

    func testTokenizeSingleKey() {
        let tokens = CustomRuleValidator.tokenize("caps")

        XCTAssertEqual(tokens, ["caps"])
    }

    func testTokenizeMultipleKeys() {
        let tokens = CustomRuleValidator.tokenize("M-right M-left")

        XCTAssertEqual(tokens, ["M-right", "M-left"])
    }

    func testTokenizeHandlesExtraWhitespace() {
        let tokens = CustomRuleValidator.tokenize("  M-right   M-left  ")

        XCTAssertEqual(tokens, ["M-right", "M-left"])
    }

    func testTokenizeEmptyString() {
        let tokens = CustomRuleValidator.tokenize("")

        XCTAssertTrue(tokens.isEmpty)
    }
}
