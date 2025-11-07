import Foundation
import XCTest

@testable import KeyPath

@MainActor
class ConfigurationServiceTests: XCTestCase {
    lazy var tempDirectory: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyPathConfigTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    lazy var configService: ConfigurationService = .init(configDirectory: tempDirectory.path)

    // MARK: - Configuration Generation Tests

    func testGenerateFromMappings_SingleMapping() {
        let mappings = [KeyMapping(input: "caps", output: "esc")]
        let config = KanataConfiguration.generateFromMappings(mappings)

        XCTAssertTrue(config.contains("(defcfg"), "Config should contain defcfg section")
        XCTAssertTrue(config.contains("process-unmapped-keys yes"), "Config should have safe defaults")
        XCTAssertTrue(config.contains("(defsrc"), "Config should contain defsrc section")
        XCTAssertTrue(config.contains("(deflayer base"), "Config should contain deflayer section")
        XCTAssertTrue(config.contains("caps"), "Config should contain caps key")
        XCTAssertTrue(config.contains("esc"), "Config should contain esc key")
    }

    func testGenerateFromMappings_MultipleMappings() {
        let mappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "a", output: "b"),
            KeyMapping(input: "c", output: "d")
        ]
        let config = KanataConfiguration.generateFromMappings(mappings)

        XCTAssertTrue(config.contains("caps"), "Config should contain all source keys")
        XCTAssertTrue(config.contains("esc"), "Config should contain all layer keys")
        XCTAssertTrue(config.contains("a"), "Config should contain 'a' key")
        XCTAssertTrue(config.contains("b"), "Config should contain 'b' key")
    }

    func testGenerateFromMappings_EmptyMappings() {
        let config = KanataConfiguration.generateFromMappings([])

        XCTAssertTrue(config.contains("(defcfg"), "Config should still contain defcfg")
        XCTAssertTrue(config.contains("(defsrc)"), "Config should contain empty defsrc")
        XCTAssertTrue(config.contains("(deflayer base)"), "Config should contain empty deflayer")
    }

    // MARK: - Configuration Parsing Tests

    func testParseConfigurationFromString_ValidConfig() throws {
        let configContent = """
        (defcfg
          process-unmapped-keys yes
        )

        (defsrc
          caps a b
        )

        (deflayer base
          esc x y
        )
        """

        let config = try configService.parseConfigurationFromString(configContent)

        XCTAssertEqual(config.keyMappings.count, 3, "Should parse 3 mappings")
        XCTAssertEqual(config.keyMappings[0].input, "caps")
        XCTAssertEqual(config.keyMappings[0].output, "esc")
        XCTAssertEqual(config.keyMappings[1].input, "a")
        XCTAssertEqual(config.keyMappings[1].output, "x")
    }

    func testParseConfigurationFromString_WithComments() throws {
        let configContent = """
        ;; This is a comment
        (defcfg
          process-unmapped-keys yes
        )

        (defsrc
          ;; Source keys comment
          caps
        )

        (deflayer base
          ;; Layer keys comment
          esc
        )
        """

        let config = try configService.parseConfigurationFromString(configContent)

        XCTAssertEqual(config.keyMappings.count, 1, "Should parse 1 mapping, ignoring comments")
        XCTAssertEqual(config.keyMappings[0].input, "caps")
        XCTAssertEqual(config.keyMappings[0].output, "esc")
    }

    func testParseConfigurationFromString_Deduplication() throws {
        let configContent = """
        (defcfg
          process-unmapped-keys yes
        )

        (defsrc
          caps caps a
        )

        (deflayer base
          esc ctrl x
        )
        """

        let config = try configService.parseConfigurationFromString(configContent)

        // Should deduplicate caps, keeping the last mapping
        XCTAssertEqual(config.keyMappings.count, 2, "Should deduplicate duplicate keys")
        let capsMapping = config.keyMappings.first { $0.input == "caps" }
        XCTAssertEqual(capsMapping?.output, "ctrl", "Should keep last mapping for caps")
    }

    // MARK: - Configuration Saving Tests

    func testSaveConfiguration_WithKeyMappings() async throws {
        let mappings = [KeyMapping(input: "caps", output: "esc")]

        try await configService.saveConfiguration(keyMappings: mappings)

        // Verify file was created
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path), "Config file should be created")

        // Verify content
        let savedContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(savedContent.contains("caps"), "Saved config should contain mapping")
        XCTAssertTrue(savedContent.contains("esc"), "Saved config should contain mapping")
    }

    func testSaveConfiguration_WithInputOutput() async throws {
        try await configService.saveConfiguration(input: "a", output: "b")

        // Verify file was created
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path), "Config file should be created")

        // Verify content
        let savedContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(savedContent.contains("a"), "Saved config should contain input")
        XCTAssertTrue(savedContent.contains("b"), "Saved config should contain output")
    }

    // MARK: - Error Parsing Tests

    func testParseKanataErrors_WithErrorTags() {
        let output = """
        [ERROR] Line 5: Invalid key 'foo'
        [ERROR] Line 10: Missing closing parenthesis
        Some other output
        """

        let errors = configService.parseKanataErrors(output)

        XCTAssertEqual(errors.count, 2, "Should parse 2 errors")
        XCTAssertTrue(errors[0].contains("Line 5"), "Should extract error details")
        XCTAssertTrue(errors[1].contains("Line 10"), "Should extract error details")
    }

    func testParseKanataErrors_NoErrorTags() {
        let output = "Some validation output without error tags"

        let errors = configService.parseKanataErrors(output)

        // Should return the full output as error if no [ERROR] tags found
        XCTAssertEqual(errors.count, 1, "Should return full output as error")
        XCTAssertEqual(errors[0], output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testParseKanataErrors_EmptyOutput() {
        let errors = configService.parseKanataErrors("")

        XCTAssertEqual(errors.count, 0, "Should return empty array for empty output")
    }

    // MARK: - Key Conversion Tests

    func testConvertToKanataKey_StandardKeys() {
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("caps"), "caps")
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("space"), "spc")
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("escape"), "esc")
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("tab"), "tab")
    }

    func testConvertToKanataKey_CaseInsensitive() {
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("CAPS"), "caps")
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("CapsLock"), "caps")
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("Caps Lock"), "caps")
    }

    func testConvertToKanataKey_ModifierKeys() {
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("cmd"), "lmet")
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("leftcmd"), "lmet")
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("left command"), "lmet")
        XCTAssertEqual(KanataKeyConverter.convertToKanataKey("left shift"), "lsft")
    }

    func testConvertToKanataSequence_SingleKey() {
        let result = KanataKeyConverter.convertToKanataSequence("esc")
        XCTAssertEqual(result, "esc", "Single key should NOT have parentheses")
        XCTAssertFalse(result.hasPrefix("("), "Single key should NOT start with parenthesis")
        XCTAssertFalse(result.hasSuffix(")"), "Single key should NOT end with parenthesis")
    }

    func testConvertToKanataSequence_SingleLongKey() {
        // BUG FIX TEST: Keys longer than 4 chars should NOT be wrapped in parentheses
        let result = KanataKeyConverter.convertToKanataSequence("escape")
        XCTAssertEqual(result, "esc", "Long single key should convert but NOT wrap in parentheses")
        XCTAssertFalse(result.hasPrefix("("), "Single key 'escape' should NOT have parentheses")
        XCTAssertFalse(result.hasSuffix(")"), "Single key 'escape' should NOT have parentheses")
    }

    func testConvertToKanataSequence_SingleKeyVariants() {
        // Test various single keys that should NEVER have parentheses
        let testCases = [
            ("tab", "tab"),
            ("space", "spc"),
            ("return", "ret"),
            ("backspace", "bspc"),
            ("delete", "del")
        ]

        for (input, expectedBase) in testCases {
            let result = KanataKeyConverter.convertToKanataSequence(input)
            XCTAssertFalse(result.hasPrefix("("), "\(input) should NOT be wrapped in parentheses")
            XCTAssertFalse(result.hasSuffix(")"), "\(input) should NOT be wrapped in parentheses")
            XCTAssertTrue(result.contains(expectedBase), "\(input) should convert to contain \(expectedBase)")
        }
    }

    func testConvertToKanataSequence_MultipleKeys() {
        let result = KanataKeyConverter.convertToKanataSequence("cmd space")
        XCTAssertTrue(result.hasPrefix("("), "Multi-key sequence SHOULD be wrapped in parentheses")
        XCTAssertTrue(result.hasSuffix(")"), "Multi-key sequence SHOULD be wrapped in parentheses")
        XCTAssertTrue(result.contains("lmet"), "Should convert cmd to lmet")
        XCTAssertTrue(result.contains("spc"), "Should convert space to spc")
    }

    func testConvertToKanataSequence_TextMacro_Numbers() {
        // Test that "123" converts to (macro 1 2 3)
        let result = KanataKeyConverter.convertToKanataSequence("123")
        XCTAssertTrue(result.hasPrefix("(macro "), "Number sequence should be wrapped in macro")
        XCTAssertTrue(result.contains("1"), "Should contain 1")
        XCTAssertTrue(result.contains("2"), "Should contain 2")
        XCTAssertTrue(result.contains("3"), "Should contain 3")
        XCTAssertEqual(result, "(macro 1 2 3)", "Should generate correct macro syntax")
    }

    func testConvertToKanataSequence_TextMacro_Letters() {
        // Test that "hello" converts to (macro h e l l o)
        let result = KanataKeyConverter.convertToKanataSequence("hello")
        XCTAssertTrue(result.hasPrefix("(macro "), "Letter sequence should be wrapped in macro")
        XCTAssertEqual(result, "(macro h e l l o)", "Should generate correct macro syntax")
    }

    func testConvertToKanataSequence_KeyNameNotMacro() {
        // Test that key names like "escape" don't get split into macros
        let escapeResult = KanataKeyConverter.convertToKanataSequence("escape")
        XCTAssertEqual(escapeResult, "esc", "escape should convert to esc, not macro")
        XCTAssertFalse(escapeResult.contains("macro"), "Key names shouldn't become macros")

        let tabResult = KanataKeyConverter.convertToKanataSequence("tab")
        XCTAssertEqual(tabResult, "tab", "tab should stay as tab")

        let spaceResult = KanataKeyConverter.convertToKanataSequence("space")
        XCTAssertEqual(spaceResult, "spc", "space should convert to spc")
    }

    func testGeneratedConfigWithTextMacro() {
        // Test that a mapping with text output generates correct macro in config
        let mappings = [
            KeyMapping(input: "1", output: "123")
        ]

        let config = KanataConfiguration.generateFromMappings(mappings)

        // Check that deflayer contains the macro
        XCTAssertTrue(config.contains("(macro 1 2 3)"), "Config should contain macro for text sequence")
        XCTAssertTrue(config.contains("(defsrc"), "Config should have defsrc")
        XCTAssertTrue(config.contains("(deflayer base"), "Config should have deflayer")
    }

    func testGeneratedConfigHasNoInvalidParentheses() {
        // REGRESSION TEST: Ensure generated configs never have (esc) or other invalid single-key wrapping
        let mappings = [
            KeyMapping(input: "caps", output: "escape"),
            KeyMapping(input: "tab", output: "backspace"),
            KeyMapping(input: "a", output: "delete")
        ]

        let config = KanataConfiguration.generateFromMappings(mappings)

        // Check that single keys are NOT wrapped in parentheses in deflayer
        XCTAssertFalse(config.contains("(esc)"), "Config should NOT contain (esc) - single keys must not be wrapped")
        XCTAssertFalse(config.contains("(bspc)"), "Config should NOT contain (bspc) - single keys must not be wrapped")
        XCTAssertFalse(config.contains("(del)"), "Config should NOT contain (del) - single keys must not be wrapped")

        // Check that they ARE present WITHOUT parentheses
        let deflayerSection = config.components(separatedBy: "(deflayer base")[1]
        XCTAssertTrue(deflayerSection.contains("esc"), "Should contain esc without parentheses")
        XCTAssertTrue(deflayerSection.contains("bspc"), "Should contain bspc without parentheses")
        XCTAssertTrue(deflayerSection.contains("del"), "Should contain del without parentheses")
    }

    // MARK: - Backup and Recovery Tests

    func testBackupFailedConfigAndApplySafe() async throws {
        let failedConfig = """
        (defcfg
          invalid-option
        )
        """
        let mappings = [KeyMapping(input: "caps", output: "esc")]

        let backupPath = try await configService.backupFailedConfigAndApplySafe(
            failedConfig: failedConfig,
            mappings: mappings
        )

        // Verify backup was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath), "Backup file should be created")

        // Verify backup contains original config
        let backupContent = try String(contentsOfFile: backupPath, encoding: .utf8)
        XCTAssertTrue(backupContent.contains(failedConfig), "Backup should contain original config")

        // Verify safe config was applied
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        let safeContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(safeContent.contains("caps"), "Safe config should be applied")
        XCTAssertTrue(safeContent.contains("escape"), "Safe config should use escape key")
    }

    func testRepairConfiguration_MissingDefcfg() async throws {
        let brokenConfig = """
        (defsrc caps)
        (deflayer base esc)
        """
        let errors = ["missing defcfg section"]
        let mappings = [KeyMapping(input: "caps", output: "esc")]

        let repairedConfig = try await configService.repairConfiguration(
            config: brokenConfig,
            errors: errors,
            mappings: mappings
        )

        XCTAssertTrue(repairedConfig.contains("(defcfg"), "Repaired config should have defcfg")
        XCTAssertTrue(
            repairedConfig.contains("process-unmapped-keys yes"),
            "Repaired config should have safe defaults"
        )
    }

    func testRepairConfiguration_MismatchedLengths() async throws {
        let brokenConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps a b)
        (deflayer base esc)
        """
        let errors = ["mismatch in defsrc and deflayer lengths"]
        let mappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "a", output: "x")
        ]

        let repairedConfig = try await configService.repairConfiguration(
            config: brokenConfig,
            errors: errors,
            mappings: mappings
        )

        // Should regenerate from mappings
        XCTAssertTrue(repairedConfig.contains("caps"), "Should contain all mappings")
        XCTAssertTrue(repairedConfig.contains("a"), "Should contain all mappings")
        XCTAssertTrue(repairedConfig.contains("esc"), "Should contain all layer keys")
        XCTAssertTrue(repairedConfig.contains("x"), "Should contain all layer keys")
    }

    // MARK: - Integration Tests

    func testRoundTrip_GenerateParseGenerate() throws {
        let originalMappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "a", output: "b")
        ]

        // Generate config
        let generatedConfig = KanataConfiguration.generateFromMappings(originalMappings)

        // Parse it back
        let parsed = try configService.parseConfigurationFromString(generatedConfig)

        // Verify mappings match
        XCTAssertEqual(parsed.keyMappings.count, originalMappings.count, "Should preserve all mappings")
        for original in originalMappings {
            let found = parsed.keyMappings.first { $0.input == original.input }
            XCTAssertNotNil(found, "Should find mapping for \(original.input)")
            XCTAssertEqual(found?.output, original.output, "Output should match for \(original.input)")
        }
    }

    // MARK: - Observer/Notification Tests

    func testObserverFiresOnMainActor_OnSave() async throws {
        let exp = expectation(description: "Observer fired on save")
        actor Flag { var value = false; func setTrue() { value = true }; func get() -> Bool { value } }
        let flag = Flag()

        _ = configService.observe { _ in
            Task { @MainActor in
                await flag.setTrue()
                exp.fulfill()
            }
        }

        try await configService.saveConfiguration(input: "caps", output: "esc")

        await fulfillment(of: [exp], timeout: 2.0)
        let fired = await flag.get()
        XCTAssertTrue(fired, "Observer should fire on main actor for UI safety")
    }

    func testObserverFiresOnMainActor_OnReload() async throws {
        // First, write a valid config file so reload succeeds
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        let content = """
        (defcfg
          process-unmapped-keys yes
        )

        (defsrc caps)
        (deflayer base esc)
        """
        try content.write(to: configPath, atomically: true, encoding: .utf8)

        let exp = expectation(description: "Observer fired on reload")
        actor Flag { var value = false; func setTrue() { value = true }; func get() -> Bool { value } }
        let flag = Flag()

        _ = configService.observe { _ in
            Task { @MainActor in
                await flag.setTrue()
                exp.fulfill()
            }
        }

        _ = try await configService.reload()

        await fulfillment(of: [exp], timeout: 2.0)
        let fired = await flag.get()
        XCTAssertTrue(fired, "Observer should fire on main actor for UI safety")
    }
}
