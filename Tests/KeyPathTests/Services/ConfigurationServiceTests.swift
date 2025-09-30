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
    lazy var configService: ConfigurationService = ConfigurationService(configDirectory: tempDirectory.path)

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
        XCTAssertEqual(result, "esc")
    }

    func testConvertToKanataSequence_MultipleKeys() {
        let result = KanataKeyConverter.convertToKanataSequence("cmd space")
        XCTAssertTrue(result.hasPrefix("("), "Multi-key sequence should be wrapped in parentheses")
        XCTAssertTrue(result.hasSuffix(")"), "Multi-key sequence should be wrapped in parentheses")
        XCTAssertTrue(result.contains("lmet"), "Should convert cmd to lmet")
        XCTAssertTrue(result.contains("spc"), "Should convert space to spc")
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
}
