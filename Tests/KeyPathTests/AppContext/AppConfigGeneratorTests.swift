@preconcurrency import XCTest

@testable import KeyPathAppKit

final class AppConfigGeneratorTests: XCTestCase {
    // MARK: - Empty Config

    func testGenerate_EmptyKeymaps_ReturnsEmptyConfig() {
        let content = AppConfigGenerator.generate(from: [])

        XCTAssertTrue(content.contains("No app keymaps configured"))
        XCTAssertFalse(content.contains("defvirtualkeys"))
    }

    func testGenerate_AllDisabled_ReturnsEmptyConfig() {
        let disabledMapping = AppKeyMapping(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            isEnabled: false
        )
        let keymap = AppKeymap(
            mapping: disabledMapping,
            overrides: [AppKeyOverride(inputKey: "j", outputAction: "down")]
        )

        let content = AppConfigGenerator.generate(from: [keymap])

        XCTAssertTrue(content.contains("No app keymaps configured"))
    }

    // MARK: - Virtual Keys Block

    func testGenerate_SingleApp_CreatesVirtualKeysBlock() {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [AppKeyOverride(inputKey: "j", outputAction: "down")]
        )

        let content = AppConfigGenerator.generate(from: [keymap])

        XCTAssertTrue(content.contains("(defvirtualkeys"))
        // Uses XX (blocked key), NOT "nop" which is invalid Kanata
        XCTAssertTrue(content.contains("vk_safari XX"), "Should use XX (blocked), not nop")
        XCTAssertFalse(content.contains(" nop"), "Should NOT contain 'nop' - it's invalid Kanata")
    }

    func testGenerate_MultipleApps_CreatesAllVirtualKeys() {
        let keymaps = [
            AppKeymap(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                overrides: [AppKeyOverride(inputKey: "j", outputAction: "down")]
            ),
            AppKeymap(
                bundleIdentifier: "com.microsoft.VSCode",
                displayName: "VS Code",
                overrides: [AppKeyOverride(inputKey: "j", outputAction: "down")]
            )
        ]

        let content = AppConfigGenerator.generate(from: keymaps)

        // Uses XX (blocked key), NOT "nop" which is invalid Kanata
        XCTAssertTrue(content.contains("vk_safari XX"), "Should use XX (blocked), not nop")
        XCTAssertTrue(content.contains("vk_vs_code XX"), "Should use XX (blocked), not nop")
        XCTAssertFalse(content.contains(" nop"), "Should NOT contain 'nop' - it's invalid Kanata")
    }

    // MARK: - Kanata Keyword Safety

    func testGenerate_UsesKanataKeywordConstant() {
        // Verifies that generated config uses KanataKeyword.blocked constant
        // This is a compile-time safety feature to prevent typos like "nop"
        let keymap = AppKeymap(
            bundleIdentifier: "com.test.app",
            displayName: "Test App",
            overrides: []
        )

        let content = AppConfigGenerator.generate(from: [keymap])

        // The config should use the constant value, which is "XX"
        XCTAssertTrue(content.contains(KanataKeyword.blocked))
        XCTAssertFalse(content.contains(" nop"))
    }

    // MARK: - Alias Block

    func testGenerate_SingleOverride_CreatesSwitchExpression() {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [AppKeyOverride(inputKey: "j", outputAction: "down")]
        )

        let content = AppConfigGenerator.generate(from: [keymap])

        XCTAssertTrue(content.contains("(defalias"))
        XCTAssertTrue(content.contains("kp-j"))
        XCTAssertTrue(content.contains("(switch"))
        XCTAssertTrue(content.contains("((input virtual vk_safari)) down"))
        XCTAssertTrue(content.contains("() j)")) // Default case
    }

    func testGenerate_MultipleOverridesForSameKey_CreatesCombinedSwitch() {
        let keymaps = [
            AppKeymap(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                overrides: [AppKeyOverride(inputKey: "j", outputAction: "down")]
            ),
            AppKeymap(
                bundleIdentifier: "com.microsoft.VSCode",
                displayName: "VS Code",
                overrides: [AppKeyOverride(inputKey: "j", outputAction: "pgdn")]
            )
        ]

        let content = AppConfigGenerator.generate(from: keymaps)

        // Should have a single kp-j alias with multiple cases
        XCTAssertTrue(content.contains("kp-j"))
        XCTAssertTrue(content.contains("vk_safari"))
        XCTAssertTrue(content.contains("vk_vs_code"))
        XCTAssertTrue(content.contains("down"))
        XCTAssertTrue(content.contains("pgdn"))
    }

    func testGenerate_NoOverrides_NoAliasBlock() {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: []
        )

        let content = AppConfigGenerator.generate(from: [keymap])

        // Should still have virtual key but no alias block
        XCTAssertTrue(content.contains("defvirtualkeys"))
        XCTAssertFalse(content.contains("defalias"))
    }

    // MARK: - Key Name Sanitization

    func testGenerate_KeyWithSpecialChars_SanitizesAliasName() {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [AppKeyOverride(inputKey: "semicolon", outputAction: "cmd")]
        )

        let content = AppConfigGenerator.generate(from: [keymap])

        XCTAssertTrue(content.contains("kp-semicolon"))
    }

    func testGenerate_KeyStartsWithNumber_AddsPrefix() {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [AppKeyOverride(inputKey: "1", outputAction: "f1")]
        )

        let content = AppConfigGenerator.generate(from: [keymap])

        // Should have key- prefix since it starts with a number
        XCTAssertTrue(content.contains("kp-key-1"))
    }

    // MARK: - Header

    func testGenerate_IncludesHeader() {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: []
        )

        let content = AppConfigGenerator.generate(from: [keymap])

        XCTAssertTrue(content.contains("Generated by KeyPath"))
        XCTAssertTrue(content.contains("DO NOT EDIT"))
        XCTAssertTrue(content.contains("Safari"))
    }

    func testGenerate_HeaderIncludesAllAppNames() {
        let keymaps = [
            AppKeymap(bundleIdentifier: "com.apple.Safari", displayName: "Safari", overrides: []),
            AppKeymap(bundleIdentifier: "com.microsoft.VSCode", displayName: "VS Code", overrides: [])
        ]

        let content = AppConfigGenerator.generate(from: keymaps)

        XCTAssertTrue(content.contains("Safari"))
        XCTAssertTrue(content.contains("VS Code"))
    }

    // MARK: - Output Action Escaping

    func testEscapeOutputAction_SimpleKey_Unchanged() {
        let escaped = AppConfigGenerator.escapeOutputAction("down")
        XCTAssertEqual(escaped, "down")
    }

    func testEscapeOutputAction_Macro_Unchanged() {
        let escaped = AppConfigGenerator.escapeOutputAction("(macro h e l l o)")
        XCTAssertEqual(escaped, "(macro h e l l o)")
    }

    func testEscapeOutputAction_AliasReference_Unchanged() {
        let escaped = AppConfigGenerator.escapeOutputAction("@my-alias")
        XCTAssertEqual(escaped, "@my-alias")
    }

    func testEscapeOutputAction_TrimsWhitespace() {
        let escaped = AppConfigGenerator.escapeOutputAction("  down  ")
        XCTAssertEqual(escaped, "down")
    }

    // MARK: - Deterministic Output

    func testGenerate_IsDeterministic() {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [
                AppKeyOverride(inputKey: "j", outputAction: "down"),
                AppKeyOverride(inputKey: "k", outputAction: "up")
            ]
        )

        let content1 = AppConfigGenerator.generate(from: [keymap])
        let content2 = AppConfigGenerator.generate(from: [keymap])

        // Excluding timestamp, content should be the same
        let lines1 = content1.split(separator: "\n").filter { !$0.contains("Generated:") }
        let lines2 = content2.split(separator: "\n").filter { !$0.contains("Generated:") }

        XCTAssertEqual(lines1, lines2)
    }

    func testGenerate_KeysAreSorted() {
        let keymap = AppKeymap(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            overrides: [
                AppKeyOverride(inputKey: "z", outputAction: "a"),
                AppKeyOverride(inputKey: "a", outputAction: "z"),
                AppKeyOverride(inputKey: "m", outputAction: "m")
            ]
        )

        let content = AppConfigGenerator.generate(from: [keymap])

        // Find positions of the aliases
        let aPos = content.range(of: "kp-a")?.lowerBound
        let mPos = content.range(of: "kp-m")?.lowerBound
        let zPos = content.range(of: "kp-z")?.lowerBound

        XCTAssertNotNil(aPos)
        XCTAssertNotNil(mPos)
        XCTAssertNotNil(zPos)

        // Should be in alphabetical order
        XCTAssertTrue(aPos! < mPos!)
        XCTAssertTrue(mPos! < zPos!)
    }

    // MARK: - AppConfigError Tests

    func testAppConfigError_ValidationFailed_HasUserFacingMessage() {
        let error = AppConfigError.validationFailed(errors: ["Unknown key: nop"])

        XCTAssertEqual(error.userFacingMessage, "Unknown key: nop")
        XCTAssertTrue(error.errorDescription?.contains("validation failed") ?? false)
    }

    func testAppConfigError_ValidationFailed_EmptyErrors_HasFallbackMessage() {
        let error = AppConfigError.validationFailed(errors: [])

        XCTAssertEqual(error.userFacingMessage, "Config validation failed")
    }

    func testAppConfigError_WriteFailed_HasUserFacingMessage() {
        let error = AppConfigError.writeFailed(path: "/tmp/test.kbd", underlying: "Permission denied")

        XCTAssertTrue(error.userFacingMessage.contains("/tmp/test.kbd"))
        XCTAssertTrue(error.errorDescription?.contains("Permission denied") ?? false)
    }

    func testAppConfigError_Equatable() {
        let error1 = AppConfigError.validationFailed(errors: ["test"])
        let error2 = AppConfigError.validationFailed(errors: ["test"])
        let error3 = AppConfigError.validationFailed(errors: ["different"])

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Regression Tests for Bug Fixes

    /// Regression test: Ensure we never generate "nop" which crashed Kanata
    /// Bug: AppConfigGenerator was using "nop" instead of "XX" for virtual keys
    /// Fix: Use KanataKeyword.blocked constant which is "XX"
    func testGenerate_NeverContainsNop_RegressionTest() {
        // Create multiple keymaps with various configurations
        let keymaps = [
            AppKeymap(bundleIdentifier: "com.apple.Safari", displayName: "Safari", overrides: []),
            AppKeymap(bundleIdentifier: "com.microsoft.VSCode", displayName: "VS Code", overrides: [
                AppKeyOverride(inputKey: "j", outputAction: "down")
            ]),
            AppKeymap(bundleIdentifier: "com.openai.ChatGPT", displayName: "ChatGPT", overrides: [
                AppKeyOverride(inputKey: "a", outputAction: "b"),
                AppKeyOverride(inputKey: "k", outputAction: "up")
            ])
        ]

        let content = AppConfigGenerator.generate(from: keymaps)

        // CRITICAL: The word "nop" should NEVER appear in generated config
        // because it's not a valid Kanata keyword and will crash Kanata
        XCTAssertFalse(
            content.contains(" nop"),
            "Generated config must NEVER contain 'nop' - it's invalid Kanata and crashes the service"
        )

        // Verify we're using the correct keyword instead
        XCTAssertTrue(content.contains(" XX"), "Should use XX (blocked key) instead of nop")
    }
}
