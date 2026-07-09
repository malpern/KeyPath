@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

final class ConflictMergeTests: XCTestCase {
    // MARK: - Two simple remaps → error

    func testMergeTwoSimpleRemapsThrows() {
        let existing = makeRule(input: "caps", action: .keystroke(key: "esc"))
        XCTAssertThrowsError(
            try RulesFacade.mergeRules(existing: existing, newAction: .keystroke(key: "lctl"), newBehavior: nil)
        ) { error in
            guard let mergeErr = error as? CLIMergeError else {
                XCTFail("Expected CLIMergeError, got \(error)")
                return
            }
            XCTAssertTrue(mergeErr.reason.contains("ambiguous"))
        }
    }

    // MARK: - Simple remap + tap-hold → merged

    func testMergeSimpleWithTapHoldUseExistingAsTap() throws {
        let existing = makeRule(input: "a", action: .keystroke(key: "a"))
        let newBehavior = MappingBehavior.dualRole(DualRoleBehavior(
            tapAction: .keystroke(key: "x"),
            holdAction: .keystroke(key: "lctl"),
            tapTimeout: 300
        ))

        let merged = try RulesFacade.mergeRules(
            existing: existing,
            newAction: .keystroke(key: "x"),
            newBehavior: newBehavior
        )

        guard case let .dualRole(dual) = merged.behavior else {
            XCTFail("Expected dualRole behavior")
            return
        }
        XCTAssertEqual(dual.tapAction, .keystroke(key: "a"), "Tap should be the existing simple action")
        XCTAssertEqual(dual.holdAction, .keystroke(key: "lctl"), "Hold should be from new behavior")
        XCTAssertEqual(dual.tapTimeout, 300)
    }

    // MARK: - Tap-hold + simple remap → update tap

    func testMergeTapHoldWithSimpleUpdatesTap() throws {
        let existing = makeRule(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"),
                holdAction: .keystroke(key: "lctl")
            ))
        )

        let merged = try RulesFacade.mergeRules(
            existing: existing,
            newAction: .keystroke(key: "esc"),
            newBehavior: nil
        )

        guard case let .dualRole(dual) = merged.behavior else {
            XCTFail("Expected dualRole behavior")
            return
        }
        XCTAssertEqual(dual.tapAction, .keystroke(key: "esc"), "Tap should update to new action")
        XCTAssertEqual(dual.holdAction, .keystroke(key: "lctl"), "Hold should remain unchanged")
    }

    // MARK: - Two tap-holds → new overrides

    func testMergeTwoTapHoldsNewOverrides() throws {
        let existing = makeRule(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: "a"),
                holdAction: .keystroke(key: "lctl"),
                tapTimeout: 200
            ))
        )

        let newDual = DualRoleBehavior(
            tapAction: .keystroke(key: "esc"),
            holdAction: .keystroke(key: "lalt"),
            tapTimeout: 300
        )

        let merged = try RulesFacade.mergeRules(
            existing: existing,
            newAction: .keystroke(key: "esc"),
            newBehavior: .dualRole(newDual)
        )

        guard case let .dualRole(dual) = merged.behavior else {
            XCTFail("Expected dualRole behavior")
            return
        }
        XCTAssertEqual(dual.tapAction, .keystroke(key: "esc"))
        XCTAssertEqual(dual.holdAction, .keystroke(key: "lalt"))
        XCTAssertEqual(dual.tapTimeout, 300)
    }

    // MARK: - Incompatible behaviors → error

    func testMergeIncompatibleBehaviorsThrows() {
        let existing = makeRule(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: .macro(MacroBehavior())
        )
        let newBehavior = MappingBehavior.dualRole(DualRoleBehavior(
            tapAction: .keystroke(key: "a"),
            holdAction: .keystroke(key: "lctl")
        ))

        XCTAssertThrowsError(
            try RulesFacade.mergeRules(existing: existing, newAction: .keystroke(key: "a"), newBehavior: newBehavior)
        ) { error in
            guard let mergeErr = error as? CLIMergeError else {
                XCTFail("Expected CLIMergeError, got \(error)")
                return
            }
            XCTAssertTrue(mergeErr.reason.contains("incompatible"))
        }
    }

    func testMergePreservesExistingRuleMetadata() throws {
        var existing = makeRule(input: "a", action: .keystroke(key: "a"))
        existing.title = "My Rule"
        existing.notes = "Important"
        existing.shiftedOutput = "A"

        let newBehavior = MappingBehavior.dualRole(DualRoleBehavior(
            tapAction: .keystroke(key: "x"),
            holdAction: .keystroke(key: "lctl")
        ))

        let merged = try RulesFacade.mergeRules(
            existing: existing,
            newAction: .keystroke(key: "x"),
            newBehavior: newBehavior
        )

        XCTAssertEqual(merged.title, "My Rule")
        XCTAssertEqual(merged.notes, "Important")
        XCTAssertEqual(merged.shiftedOutput, "A")
        XCTAssertEqual(merged.id, existing.id)
    }

    // MARK: - Helpers

    private func makeRule(
        input: String,
        action: KeyAction,
        behavior: MappingBehavior? = nil
    ) -> CustomRule {
        CustomRule(
            input: input,
            action: action,
            behavior: behavior
        )
    }
}
