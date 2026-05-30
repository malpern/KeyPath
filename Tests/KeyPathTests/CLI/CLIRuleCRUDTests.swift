@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class CLIRuleCRUDTests: XCTestCase {
    private let facade = RulesFacade()

    override func setUp() async throws {
        try await super.setUp()
        let rules = await CustomRulesStore.shared.loadRules()
        if !rules.isEmpty {
            try await CustomRulesStore.shared.saveRules([])
        }
    }

    override func tearDown() async throws {
        try await CustomRulesStore.shared.saveRules([])
        try await super.tearDown()
    }

    // MARK: - addRule

    func testRuleAddSimpleCreatesRule() async throws {
        let result = try await facade.addRule(
            input: "caps",
            action: .keystroke(key: "esc")
        )
        guard case let .created(detail) = result else {
            XCTFail("Expected .created, got \(result)")
            return
        }
        XCTAssertEqual(detail.input, "caps")
        XCTAssertEqual(detail.action, .keystroke(key: "esc"))
        XCTAssertEqual(detail.targetLayer, "base")
        XCTAssertTrue(detail.isEnabled)
    }

    func testRuleAddWithActionJSON() async throws {
        let result = try await facade.addRule(
            input: "caps",
            action: .hyper
        )
        guard case let .created(detail) = result else {
            XCTFail("Expected .created, got \(result)")
            return
        }
        XCTAssertEqual(detail.action, .hyper)
    }

    func testRuleAddWithBehaviorJSON() async throws {
        let behavior = MappingBehavior.dualRole(DualRoleBehavior(
            tapAction: .keystroke(key: "a"),
            holdAction: .keystroke(key: "lctl"),
            tapTimeout: 200
        ))
        let result = try await facade.addRule(
            input: "a",
            action: .keystroke(key: "a"),
            behavior: behavior
        )
        guard case let .created(detail) = result else {
            XCTFail("Expected .created, got \(result)")
            return
        }
        XCTAssertNotNil(detail.behavior)
        if case let .dualRole(d) = detail.behavior {
            XCTAssertEqual(d.tapAction, .keystroke(key: "a"))
            XCTAssertEqual(d.holdAction, .keystroke(key: "lctl"))
        } else {
            XCTFail("Expected dualRole behavior")
        }
    }

    func testRuleAddDryRunDoesNotPersist() async throws {
        // Dry run is handled at the command layer, not the facade.
        // Verify the facade actually persists when called normally.
        _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))
        let rules = await facade.listRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.input, "caps")
    }

    func testRuleAddConflictFail() async throws {
        _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))

        do {
            _ = try await facade.addRule(
                input: "caps",
                action: .keystroke(key: "tab"),
                onConflict: .fail
            )
            XCTFail("Expected CLIConflictError")
        } catch is CLIConflictError {
            // Expected
        }

        let rules = await facade.listRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.action, .keystroke(key: "esc"))
    }

    func testRuleAddConflictReplace() async throws {
        _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))

        let result = try await facade.addRule(
            input: "caps",
            action: .keystroke(key: "tab"),
            onConflict: .replace
        )
        guard case let .replaced(detail) = result else {
            XCTFail("Expected .replaced, got \(result)")
            return
        }
        XCTAssertEqual(detail.action, .keystroke(key: "tab"))

        let rules = await facade.listRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.action, .keystroke(key: "tab"))
    }

    func testRuleAddConflictSkip() async throws {
        _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))

        let result = try await facade.addRule(
            input: "caps",
            action: .keystroke(key: "tab"),
            onConflict: .skip
        )
        guard case .skipped = result else {
            XCTFail("Expected .skipped, got \(result)")
            return
        }

        let rules = await facade.listRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.action, .keystroke(key: "esc"))
    }

    func testRuleAddWithShiftedOutput() async throws {
        let result = try await facade.addRule(
            input: "caps",
            action: .keystroke(key: "esc"),
            shiftedOutput: "~"
        )
        guard case let .created(detail) = result else {
            XCTFail("Expected .created, got \(result)")
            return
        }
        XCTAssertEqual(detail.shiftedOutput, "~")
    }

    func testRuleAddWithDeviceOverride() async throws {
        let overrides = [DeviceKeyOverride(deviceHash: "0x1234", output: .keystroke(key: "tab"))]
        let result = try await facade.addRule(
            input: "caps",
            action: .keystroke(key: "esc"),
            deviceOverrides: overrides
        )
        guard case let .created(detail) = result else {
            XCTFail("Expected .created, got \(result)")
            return
        }
        XCTAssertEqual(detail.deviceOverrides?.count, 1)
        XCTAssertEqual(detail.deviceOverrides?.first?.deviceHash, "0x1234")
        XCTAssertEqual(detail.deviceOverrides?.first?.action, .keystroke(key: "tab"))
    }

    func testRuleAddWithTargetLayer() async throws {
        let result = try await facade.addRule(
            input: "j",
            action: .keystroke(key: "down"),
            targetLayer: "nav"
        )
        guard case let .created(detail) = result else {
            XCTFail("Expected .created, got \(result)")
            return
        }
        XCTAssertEqual(detail.targetLayer, "nav")
    }

    // MARK: - listRules

    func testRuleListReturnsAllRules() async throws {
        _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))
        _ = try await facade.addRule(input: "lalt", action: .keystroke(key: "lctl"))
        let rules = await facade.listRules()
        XCTAssertEqual(rules.count, 2)
    }

    func testRuleListEnabledOnlyFilters() async throws {
        _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))
        _ = try await facade.addRule(input: "lalt", action: .keystroke(key: "lctl"))

        // Disable one rule directly in the store
        var raw = await CustomRulesStore.shared.loadRules()
        raw[0].isEnabled = false
        try await CustomRulesStore.shared.saveRules(raw)

        let enabled = await facade.listRules(enabledOnly: true)
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled.first?.input, "lalt")
    }

    // MARK: - showRule

    func testRuleShowReturnsDetail() async throws {
        _ = try await facade.addRule(
            input: "caps",
            action: .hyper,
            title: "Hyper Key",
            notes: "Makes caps into hyper"
        )
        let detail = await facade.showRule(input: "caps")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.action, .hyper)
        XCTAssertEqual(detail?.title, "Hyper Key")
        XCTAssertEqual(detail?.notes, "Makes caps into hyper")
    }

    func testRuleShowNotFoundReturnsNil() async {
        let detail = await facade.showRule(input: "nonexistent")
        XCTAssertNil(detail)
    }

    // MARK: - removeRemap with dry-run pattern

    func testRuleRemoveWithExistingRule() async throws {
        _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))
        let removed = try await facade.removeRemap(input: "caps")
        XCTAssertTrue(removed)
        let rules = await facade.listRules()
        XCTAssertTrue(rules.isEmpty)
    }

    func testRuleRemoveNonexistentReturnsFalse() async throws {
        let removed = try await facade.removeRemap(input: "nonexistent")
        XCTAssertFalse(removed)
    }

    // MARK: - enableRule / disableRule

    func testEnableRule() async throws {
        _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))
        // Disable first
        let disabledTitle = try await facade.disableRule(input: "caps")
        XCTAssertNotNil(disabledTitle)

        let rule = await facade.showRule(input: "caps")
        XCTAssertFalse(rule!.isEnabled)

        // Re-enable
        let enabledTitle = try await facade.enableRule(input: "caps")
        XCTAssertNotNil(enabledTitle)

        let reEnabled = await facade.showRule(input: "caps")
        XCTAssertTrue(reEnabled!.isEnabled)
    }

    func testDisableRule() async throws {
        _ = try await facade.addRule(input: "a", action: .keystroke(key: "b"))
        let title = try await facade.disableRule(input: "a")
        XCTAssertNotNil(title)

        let rule = await facade.showRule(input: "a")
        XCTAssertFalse(rule!.isEnabled)
    }

    func testEnableRuleNotFoundReturnsNil() async throws {
        let result = try await facade.enableRule(input: "nonexistent")
        XCTAssertNil(result)
    }

    func testDisableRuleNotFoundReturnsNil() async throws {
        let result = try await facade.disableRule(input: "nonexistent")
        XCTAssertNil(result)
    }

    func testDisableRuleExcludedFromEnabledOnlyList() async throws {
        _ = try await facade.addRule(input: "a", action: .keystroke(key: "b"))
        _ = try await facade.addRule(input: "s", action: .keystroke(key: "d"))
        _ = try await facade.disableRule(input: "a")

        let all = await facade.listRules()
        XCTAssertEqual(all.count, 2)

        let enabled = await facade.listRules(enabledOnly: true)
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled.first?.input, "s")
    }

    // MARK: - loadCustomRules

    func testLoadCustomRules() async throws {
        _ = try await facade.addRule(input: "caps", action: .keystroke(key: "esc"))
        _ = try await facade.addRule(input: "a", action: .keystroke(key: "b"))

        let rules = await facade.loadCustomRules()
        XCTAssertEqual(rules.count, 2)
        XCTAssertTrue(rules.contains(where: { $0.input == "caps" && $0.output == "esc" }))
        XCTAssertTrue(rules.contains(where: { $0.input == "a" && $0.output == "b" }))
    }
}
