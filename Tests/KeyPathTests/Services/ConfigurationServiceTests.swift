import Foundation
@preconcurrency import XCTest

@testable import KeyPathAppKit
@testable import KeyPathCore

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
        XCTAssertTrue(
            config.contains("process-unmapped-keys yes"), "Config should pass through unmapped keys"
        )
        XCTAssertTrue(config.contains("(defsrc"), "Config should contain defsrc section")
        XCTAssertTrue(config.contains("(deflayer base"), "Config should contain deflayer section")
        XCTAssertTrue(
            config.contains(";; === Collection: Custom Mappings (enabled) ==="),
            "Config should label the custom collection as enabled"
        )
        XCTAssertTrue(
            config.contains(";; === Collection: macOS Function Keys (enabled) ==="),
            "Config should always inject the macOS Function Keys collection"
        )
        XCTAssertTrue(
            config.contains(";; Enabled:"),
            "Header should list enabled collections"
        )
        XCTAssertTrue(config.contains("caps"), "Config should contain caps key")
        XCTAssertTrue(config.contains("esc"), "Config should contain esc key")
        XCTAssertTrue(config.contains("f1"), "Config should include F-key mappings")
        XCTAssertTrue(config.contains("brdn"), "Config should map F1 to brightness down")
    }

    func testGenerateFromMappings_MultipleMappings() {
        let mappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "a", output: "b"),
            KeyMapping(input: "c", output: "d")
        ]
        let config = KanataConfiguration.generateFromMappings(mappings)

        XCTAssertTrue(
            config.contains(";; === Collection: Custom Mappings (enabled) ==="),
            "Multi-mapping config should still emit the custom collection header"
        )
        XCTAssertTrue(
            config.contains(";; Enabled:"),
            "Header should list enabled collections"
        )
        XCTAssertTrue(config.contains("caps"), "Config should contain all source keys")
        XCTAssertTrue(config.contains("esc"), "Config should contain all layer keys")
        XCTAssertTrue(config.contains("a"), "Config should contain 'a' key")
        XCTAssertTrue(config.contains("b"), "Config should contain 'b' key")
    }

    func testGenerateFromMappings_EmptyMappings() {
        let config = KanataConfiguration.generateFromMappings([])

        XCTAssertTrue(config.contains("(defcfg"), "Config should still contain defcfg")
        XCTAssertTrue(
            config.contains(";; === Collection: macOS Function Keys (enabled) ==="),
            "Default macOS Function Keys collection should be emitted"
        )
        XCTAssertFalse(
            config.contains("Custom Mappings"),
            "Empty mappings should not emit a synthetic custom collection"
        )
        XCTAssertTrue(config.contains("f1"), "F keys should still be present")
    }

    func testGenerateFromMappings_UsesSingleDefsrcAndDeflayer() {
        let mappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "a", output: "b")
        ]

        let config = KanataConfiguration.generateFromMappings(mappings)
        let defsrcCount =
            config
                .components(separatedBy: .newlines)
                .filter { $0.contains("(defsrc") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix(";;") }
                .count
        let deflayerCount =
            config
                .components(separatedBy: .newlines)
                .filter {
                    $0.contains("(deflayer base") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix(";;")
                }
                .count

        XCTAssertEqual(defsrcCount, 1, "Kanata accepts exactly one defsrc block")
        XCTAssertEqual(deflayerCount, 1, "Kanata accepts exactly one deflayer block")
    }

    func testDisablingMacFunctionKeysRemovesSpecialMappings() {
        let custom = RuleCollection(
            name: "Custom",
            summary: "User mappings",
            category: .custom,
            mappings: [KeyMapping(input: "caps", output: "esc")],
            isEnabled: true,
            isSystemDefault: false
        )
        let macDisabled = RuleCollection(
            id: RuleCollectionIdentifier.macFunctionKeys,
            name: "macOS Function Keys",
            summary: "Preserves brightness, volume, and media control keys (F1-F12).",
            category: .system,
            mappings: [
                KeyMapping(input: "f1", output: "brdn"),
                KeyMapping(input: "f2", output: "brup")
            ],
            isEnabled: false,
            isSystemDefault: true
        )

        let config = KanataConfiguration.generateFromCollections([custom, macDisabled])

        let baseLayer = extractLayer(named: "base", from: config)
        XCTAssertFalse(
            baseLayer.contains("brdn"), "Disabled macOS keys should not emit macros in active layers"
        )
        // ADR-025: Disabled collections are NOT written to config (JSON stores are source of truth)
        XCTAssertFalse(
            config.contains("macOS Function Keys"),
            "Disabled collections should not appear in config output"
        )
        XCTAssertTrue(config.contains("(defsrc"))
        XCTAssertTrue(config.contains("(deflayer base"))
        XCTAssertFalse(
            config.contains("(deflayer nav)"),
            "Navigation layer should not render when mac collection disabled"
        )
    }

    func testNavigationCollectionProducesSeparateLayerAndAlias() {
        let nav = RuleCollection(
            id: RuleCollectionIdentifier.vimNavigation,
            name: "Vim Navigation",
            summary: "Arrow keys on home row",
            category: .navigation,
            mappings: [
                KeyMapping(input: "h", output: "left"),
                KeyMapping(input: "j", output: "down")
            ],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let config = KanataConfiguration.generateFromCollections([nav])

        XCTAssertTrue(config.contains("(defalias"), "Momentary activators require aliases")
        XCTAssertTrue(
            config.contains("layer_nav_spc"), "Alias name should reference navigation layer + key"
        )
        // Momentary activator uses layer-while-held for navigation
        XCTAssertTrue(
            config.contains("(layer-while-held nav)"),
            "Should use layer-while-held for momentary activator"
        )

        let baseLayer = extractLayer(named: "base", from: config)
        XCTAssertTrue(baseLayer.contains("h"), "Base layer should keep normal h key")
        // Base layer may contain "left" for the physical arrow key (pass-through)
        // but h should output h, not left - verify h's line doesn't contain "left"
        let hLine = baseLayer.split(separator: "\n").first { $0.contains("h") && !$0.hasPrefix(";") }
        XCTAssertNotNil(hLine, "Should find h key line in base layer")
        XCTAssertFalse(hLine?.contains("left") ?? true, "h should output h in base layer, not left")

        let navLayer = extractLayer(named: "nav", from: config)
        XCTAssertTrue(navLayer.contains("left"), "Navigation layer should emit arrow outputs")
        XCTAssertTrue(
            navLayer.contains("XX"), "Navigation layer should block non-nav keys with XX placeholders"
        )
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
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: configPath.path), "Config file should be created"
        )

        // Verify content
        let savedContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(savedContent.contains("caps"), "Saved config should contain mapping")
        XCTAssertTrue(savedContent.contains("esc"), "Saved config should contain mapping")
    }

    func testSaveConfiguration_WithInputOutput() async throws {
        try await configService.saveConfiguration(input: "a", output: "b")

        // Verify file was created
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: configPath.path), "Config file should be created"
        )

        // Verify content
        let savedContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(savedContent.contains("a"), "Saved config should contain input")
        XCTAssertTrue(savedContent.contains("b"), "Saved config should contain output")
    }

    func testSaveConfiguration_WithRuleCollections() async throws {
        let enabled = RuleCollection(
            name: "Test",
            summary: "Enabled collection",
            category: .custom,
            mappings: [KeyMapping(input: "caps", output: "esc")],
            isEnabled: true,
            isSystemDefault: false
        )
        let disabled = RuleCollection(
            name: "Disabled",
            summary: "Should not appear",
            category: .experimental,
            mappings: [KeyMapping(input: "x", output: "y")],
            isEnabled: false,
            isSystemDefault: false
        )

        try await configService.saveConfiguration(ruleCollections: [enabled, disabled])

        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        let savedContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(savedContent.contains("caps"))
        XCTAssertTrue(savedContent.contains("esc"))
        XCTAssertTrue(
            savedContent.contains(";; === Collection: macOS Function Keys (enabled) ==="),
            "Generated config should always include the macOS Function Keys section"
        )
        // ADR-025: Disabled collections are NOT written to config (JSON stores are source of truth)
        XCTAssertFalse(
            savedContent.contains("Disabled"),
            "Disabled collections should not appear in config output"
        )

        let parsed = try configService.parseConfigurationFromString(savedContent)
        let capsMappings = parsed.keyMappings.filter { $0.input == "caps" }
        XCTAssertEqual(capsMappings.count, 1)
        XCTAssertEqual(capsMappings.first?.output, "esc")
        XCTAssertTrue(
            parsed.keyMappings.allSatisfy { $0.input != "x" },
            "Disabled collection should not produce mappings"
        )
    }

    func testSaveConfiguration_WithCustomRules() async throws {
        let preset = RuleCollection(
            name: "Preset",
            summary: "Preset summary",
            category: .system,
            mappings: [KeyMapping(input: "f1", output: "brdn")],
            isEnabled: true,
            isSystemDefault: true
        )
        let customRules = [
            CustomRule(title: "Caps Escape", input: "caps", output: "esc"),
            CustomRule(
                title: "Space Layer", input: "space", output: "nav", isEnabled: false,
                notes: "Disabled nav layer"
            )
        ]

        try await configService.saveConfiguration(ruleCollections: [preset], customRules: customRules)

        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        let savedContent = try String(contentsOf: configPath, encoding: .utf8)
        XCTAssertTrue(
            savedContent.contains("Caps Escape"), "Custom rule title should be rendered in metadata"
        )
        XCTAssertTrue(savedContent.contains("caps"), "Enabled custom rule input should be present")
        XCTAssertTrue(savedContent.contains("esc"), "Enabled custom rule output should be present")
        // ADR-025: Disabled rules are NOT written to config (JSON stores are source of truth)
        XCTAssertFalse(
            savedContent.contains("Space Layer"),
            "Disabled custom rules should not appear in config output"
        )
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

    // MARK: - Test-Mode Validation

    func testValidateConfigurationInTestModePasses() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let configContent = """
        (defcfg
          process-unmapped-keys yes
        )

        (defsrc
          caps
        )

        (deflayer base
          esc
        )
        """

        let result = await configService.validateConfiguration(configContent)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testValidateConfigurationInTestModeRejectsEmptyContent() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let result = await configService.validateConfiguration("   ")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, "Configuration content is empty")
    }

    func testValidateConfigViaFileSkipsBinaryInTestMode() async {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (isValid, errors) = await configService.validateConfigViaFile()
        XCTAssertTrue(isValid)
        XCTAssertTrue(errors.isEmpty)
    }

    func testCreateInitialConfigWritesDefaultFile() async throws {
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        try? FileManager.default.removeItem(at: configPath)

        try await configService.createInitialConfigIfNeeded()

        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
        let contents = try String(contentsOf: configPath, encoding: .utf8)
        XCTAssertTrue(contents.contains("process-unmapped-keys yes"))
    }

    func testBackupFailedConfigAppliesSafeDefaults() async throws {
        let original = """
        (defcfg)
        (defsrc caps)
        (deflayer base esc)
        """
        let mappings = [KeyMapping(input: "caps", output: "esc")]

        let backupPath = try await configService.backupFailedConfigAndApplySafe(
            failedConfig: original, mappings: mappings
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))

        let safeContents = try String(
            contentsOf: tempDirectory.appendingPathComponent("keypath.kbd"), encoding: .utf8
        )
        XCTAssertTrue(safeContents.contains("process-unmapped-keys yes"))
        XCTAssertTrue(safeContents.contains("esc"))
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
            XCTAssertTrue(
                result.contains(expectedBase), "\(input) should convert to contain \(expectedBase)"
            )
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
        XCTAssertFalse(
            config.contains("(esc)"), "Config should NOT contain (esc) - single keys must not be wrapped"
        )
        XCTAssertFalse(
            config.contains("(bspc)"),
            "Config should NOT contain (bspc) - single keys must not be wrapped"
        )
        XCTAssertFalse(
            config.contains("(del)"), "Config should NOT contain (del) - single keys must not be wrapped"
        )

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
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupPath), "Backup file should be created"
        )

        // Verify backup contains original config
        let backupContent = try String(contentsOfFile: backupPath, encoding: .utf8)
        XCTAssertTrue(backupContent.contains(failedConfig), "Backup should contain original config")

        // Verify safe config was applied
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        let safeContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(safeContent.contains("caps"), "Safe config should be applied")
        XCTAssertTrue(safeContent.contains("esc"), "Safe config should use escape key")
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
        XCTAssertTrue(
            repairedConfig.contains("danger-enable-cmd yes"),
            "Repaired config should include command key safety toggle"
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

    // MARK: - Fork Config Generation Tests

    func testForkAliasGeneration_ShiftedOutput() {
        // Test that mappings with shiftedOutput generate fork aliases
        let nav = RuleCollection(
            id: RuleCollectionIdentifier.vimNavigation,
            name: "Vim Navigation",
            summary: "Arrow keys with fork support",
            category: .navigation,
            mappings: [
                KeyMapping(input: "g", output: "M-up", shiftedOutput: "M-down")
            ],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let config = KanataConfiguration.generateFromCollections([nav])

        // Should have defalias section with fork
        XCTAssertTrue(config.contains("(defalias"), "Config should have defalias for fork")
        XCTAssertTrue(config.contains("fork_nav_g"), "Config should have fork alias for g")
        XCTAssertTrue(config.contains("(fork"), "Config should contain fork action")
        // Fork with single key should use (multi ...) format
        XCTAssertTrue(config.contains("(multi lmet up)"), "Default output should use (multi lmet up)")
        XCTAssertTrue(config.contains("(multi lmet down)"), "Shifted output should use (multi lmet down)")
        XCTAssertTrue(config.contains("(lsft rsft)"), "Fork should trigger on shift keys")
    }

    func testForkAliasGeneration_CtrlOutput() {
        // Test that mappings with ctrlOutput generate fork aliases
        let nav = RuleCollection(
            id: RuleCollectionIdentifier.vimNavigation,
            name: "Vim Navigation",
            summary: "Page navigation with ctrl",
            category: .navigation,
            mappings: [
                KeyMapping(input: "d", output: "A-bspc", ctrlOutput: "pgdn")
            ],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let config = KanataConfiguration.generateFromCollections([nav])

        XCTAssertTrue(config.contains("(defalias"), "Config should have defalias for fork")
        XCTAssertTrue(config.contains("fork_nav_d"), "Config should have fork alias for d")
        XCTAssertTrue(config.contains("(fork"), "Config should contain fork action")
        XCTAssertTrue(config.contains("(multi lalt bspc)"), "Default output should use (multi lalt bspc)")
        XCTAssertTrue(config.contains("pgdn"), "Ctrl output should be pgdn")
        XCTAssertTrue(config.contains("(lctl rctl)"), "Fork should trigger on ctrl keys")
    }

    func testForkAliasGeneration_MacroWithUppercaseModifiers() {
        // Test that multi-key sequences in fork use macro with UPPERCASE modifier prefixes
        let nav = RuleCollection(
            id: RuleCollectionIdentifier.vimNavigation,
            name: "Vim Navigation",
            summary: "Line operations with macro",
            category: .navigation,
            mappings: [
                KeyMapping(input: "o", output: "M-right ret", shiftedOutput: "up M-right ret")
            ],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        let config = KanataConfiguration.generateFromCollections([nav])

        XCTAssertTrue(config.contains("(defalias"), "Config should have defalias")
        XCTAssertTrue(config.contains("fork_nav_o"), "Config should have fork alias for o")
        // Macros should use uppercase M-right, not lowercase m-right
        XCTAssertTrue(config.contains("(macro M-right ret)"), "Default macro should have uppercase M-right")
        XCTAssertTrue(
            config.contains("(macro up M-right ret)"), "Shifted macro should have uppercase M-right"
        )
        // Should NOT have lowercase m-right which is invalid
        XCTAssertFalse(config.contains("m-right"), "Config should NOT have lowercase m-right")
    }

    func testVimTransparentModeOffBlocksUnmappedKeys() {
        // Vim collection with transparent mode disabled should block unmapped keys in navigation layer
        let nav = RuleCollection(
            id: RuleCollectionIdentifier.vimNavigation,
            name: "Vim Navigation",
            summary: "Vim-style navigation",
            category: .navigation,
            mappings: [
                KeyMapping(input: "h", output: "left")
            ],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation),
            configuration: .table
        )

        let config = KanataConfiguration.generateFromCollections([nav])

        // Unmapped alpha key like "a" should be blocked (XX) in navigation layer
        XCTAssertTrue(config.contains("(deflayer nav"), "Should render navigation layer")
        XCTAssertTrue(config.contains("XX"), "Navigation layer should include blocked XX entries")
        // Ensure the mapped key still appears with its action
        XCTAssertTrue(config.contains("left"), "Mapped action should remain present")
    }

    func testConvertToKanataKeyForMacro_PreservesUppercaseModifiers() {
        // Test the key converter preserves modifier prefix case
        XCTAssertEqual(
            KanataKeyConverter.convertToKanataKeyForMacro("M-right"),
            "M-right",
            "Should preserve uppercase M-"
        )
        XCTAssertEqual(
            KanataKeyConverter.convertToKanataKeyForMacro("M-S-g"),
            "M-S-g",
            "Should preserve uppercase M-S-"
        )
        XCTAssertEqual(
            KanataKeyConverter.convertToKanataKeyForMacro("A-left"),
            "A-left",
            "Should preserve uppercase A-"
        )
        XCTAssertEqual(
            KanataKeyConverter.convertToKanataKeyForMacro("ret"),
            "ret",
            "Non-modifier keys should use standard conversion"
        )
        XCTAssertEqual(
            KanataKeyConverter.convertToKanataKeyForMacro("up"),
            "up",
            "Arrow keys should pass through"
        )
    }

    // MARK: - Chord Mapping Tests

    /// Test that chord mappings (simultaneous key presses like "lsft rsft") generate defchordsv2 blocks
    func testChordMappingGeneratesDefchordsv2() {
        // Create a collection with a chord mapping (input has space = multiple keys)
        let backupCapsLock = RuleCollection(
            id: RuleCollectionIdentifier.backupCapsLock,
            name: "Backup Caps Lock",
            summary: "Both Shifts toggles Caps Lock",
            category: .productivity,
            mappings: [
                KeyMapping(input: "lsft rsft", output: "caps", description: "Both Shifts → Caps Lock")
            ],
            isEnabled: true, // MUST be enabled
            isSystemDefault: false
        )

        let config = KanataConfiguration.generateFromCollections([backupCapsLock])

        // CRITICAL: defchordsv2 block must be generated for chord mappings
        XCTAssertTrue(
            config.contains("(defchordsv2"),
            "Config MUST contain defchordsv2 block for chord mappings. Got:\n\(config)"
        )
        XCTAssertTrue(
            config.contains("(lsft rsft) caps"),
            "Chord mapping should have correct syntax: (lsft rsft) caps. Got:\n\(config)"
        )
        XCTAssertTrue(
            config.contains("$chord-timeout all-released"),
            "Chord should have timeout and release behavior"
        )

        // Chord mappings should NOT appear in defsrc (they're handled separately)
        let defsrcSection = extractDefsrc(from: config)
        XCTAssertFalse(
            defsrcSection.contains("lsft rsft"),
            "Chord input 'lsft rsft' should NOT appear in defsrc - it's not a valid single key"
        )
    }

    /// Test that disabled chord collections don't generate defchordsv2
    func testDisabledChordCollectionDoesNotGenerateDefchordsv2() {
        let backupCapsLock = RuleCollection(
            id: RuleCollectionIdentifier.backupCapsLock,
            name: "Backup Caps Lock",
            summary: "Both Shifts toggles Caps Lock",
            category: .productivity,
            mappings: [
                KeyMapping(input: "lsft rsft", output: "caps")
            ],
            isEnabled: false, // DISABLED
            isSystemDefault: false
        )

        let config = KanataConfiguration.generateFromCollections([backupCapsLock])

        // Disabled collections should NOT generate defchordsv2
        XCTAssertFalse(
            config.contains("(defchordsv2"),
            "Disabled chord collection should NOT generate defchordsv2 block"
        )

        // ADR-025: Disabled collections are NOT written to config (JSON stores are source of truth)
        XCTAssertFalse(
            config.contains("Backup Caps Lock"),
            "Disabled collections should not appear in config output"
        )
    }

    /// Test that regular mappings still work alongside chord mappings
    func testMixedRegularAndChordMappings() {
        let regularCollection = RuleCollection(
            name: "Regular",
            summary: "Regular mapping",
            category: .custom,
            mappings: [KeyMapping(input: "caps", output: "esc")],
            isEnabled: true
        )

        let chordCollection = RuleCollection(
            id: RuleCollectionIdentifier.backupCapsLock,
            name: "Backup Caps Lock",
            summary: "Both Shifts toggles Caps Lock",
            category: .productivity,
            mappings: [KeyMapping(input: "lsft rsft", output: "caps")],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([regularCollection, chordCollection])

        // Should have both regular defsrc/deflayer AND defchordsv2
        XCTAssertTrue(config.contains("(defsrc"), "Should have defsrc for regular mappings")
        XCTAssertTrue(config.contains("(deflayer base"), "Should have deflayer for regular mappings")
        XCTAssertTrue(config.contains("caps"), "Regular mapping should be in defsrc")
        XCTAssertTrue(config.contains("esc"), "Regular mapping output should be in deflayer")

        // AND should have defchordsv2 for chord mapping
        XCTAssertTrue(config.contains("(defchordsv2"), "Should have defchordsv2 for chord mapping")
        XCTAssertTrue(config.contains("(lsft rsft) caps"), "Chord syntax should be correct")
    }

    func testKeyboardGridFormattingKeepsLayoutOrder() {
        let collection = RuleCollection(
            name: "Grid",
            summary: "layout",
            category: .custom,
            mappings: [
                KeyMapping(input: "q", output: "q"),
                KeyMapping(input: "p", output: "p"),
                KeyMapping(input: "space", output: "space")
            ],
            isEnabled: true
        )

        let config = KanataConfiguration.generateFromCollections([collection])
        let defsrc = extractDefsrc(from: config)
        let rows = defsrc.split(separator: "\n").map(String.init)

        guard let rowWithQ = rows.first(where: { $0.contains("q") && $0.contains("p") }) else {
            XCTFail("Expected a row containing q and p in keyboard order")
            return
        }
        let qPos = rowWithQ.range(of: "q")!.lowerBound
        let pPos = rowWithQ.range(of: "p")!.lowerBound
        XCTAssertLessThan(qPos, pPos, "q should appear before p following physical layout")

        let spaceRow = rows.first { $0.contains("spc") }
        XCTAssertNotNil(spaceRow, "Space bar row should be present")
        if let row = spaceRow {
            XCTAssertTrue(row.contains("spc"), "Space should be rendered as spc for defsrc")
        }
    }

    /// Helper to extract defsrc section
    private func extractDefsrc(from config: String) -> String {
        guard let start = config.range(of: "(defsrc") else { return "" }
        let suffix = config[start.lowerBound...]
        guard let end = suffix.range(of: "\n)") else { return String(suffix) }
        return String(suffix[..<end.upperBound])
    }

    /// Test that enabled Backup Caps Lock from catalog generates defchordsv2
    func testBackupCapsLockFromCatalogGeneratesDefchordsv2() {
        // Get the actual catalog collection
        let catalog = RuleCollectionCatalog()
        let defaultCollections = catalog.defaultCollections()

        // Find and enable the Backup Caps Lock collection
        var collections = defaultCollections
        if let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.backupCapsLock }) {
            collections[index].isEnabled = true
        }

        let config = KanataConfiguration.generateFromCollections(collections)

        // Debug: print the enabled state
        let backupCollection = collections.first { $0.id == RuleCollectionIdentifier.backupCapsLock }
        XCTAssertNotNil(backupCollection, "Backup Caps Lock should exist in catalog")
        XCTAssertTrue(backupCollection?.isEnabled ?? false, "Backup Caps Lock should be enabled")
        XCTAssertEqual(backupCollection?.mappings.first?.input, "lsft rsft", "Should have chord mapping")

        // The critical assertion
        XCTAssertTrue(
            config.contains("(defchordsv2"),
            "Enabled Backup Caps Lock MUST generate defchordsv2. Config:\n\(config.prefix(2000))"
        )
        XCTAssertTrue(
            config.contains("(lsft rsft) caps"),
            "Chord syntax must be correct"
        )
    }

    /// Test that upgradedCollection preserves isEnabled for Backup Caps Lock
    func testUpgradedCollectionPreservesEnabledState() {
        let catalog = RuleCollectionCatalog()

        // Simulate a stored collection with isEnabled: true
        let storedCollection = RuleCollection(
            id: RuleCollectionIdentifier.backupCapsLock,
            name: "Backup Caps Lock",
            summary: "Old summary",
            category: .productivity,
            mappings: [KeyMapping(input: "old", output: "old")],
            isEnabled: true // User enabled this
        )

        let upgraded = catalog.upgradedCollection(from: storedCollection)

        // isEnabled should be preserved from stored collection
        XCTAssertTrue(upgraded.isEnabled, "upgradedCollection must preserve isEnabled from stored collection")
        // But mappings should come from catalog
        XCTAssertEqual(upgraded.mappings.first?.input, "lsft rsft", "Mappings should come from catalog")
    }

    // MARK: - Integration Tests

    /// CRITICAL: This test validates that the default RuleCollectionCatalog generates
    /// valid Kanata config. This catches syntax errors introduced in catalog mappings
    /// during the build process, before they reach users.
    func testDefaultCatalogGeneratesValidKanataConfig() async throws {
        // Find kanata binary - try multiple locations
        let kanataBinary = try findKanataBinary()
        try await validateCatalogConfig(withBinary: kanataBinary)
    }

    /// Find the kanata binary, checking multiple locations
    private func findKanataBinary() throws -> String {
        // Get project root from this test file's location
        // #file = .../Tests/KeyPathTests/Services/ConfigurationServiceTests.swift
        let testFile = URL(fileURLWithPath: #file)
        let projectRoot = testFile
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // KeyPathTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // project root

        // Candidate locations in priority order
        let candidates = [
            // Local dev build
            projectRoot.appendingPathComponent("dist/KeyPath.app/Contents/Library/KeyPath/kanata").path,
            // Installed app
            "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata",
            // External kanata build (for CI or fresh clones)
            projectRoot.appendingPathComponent("External/kanata/target/aarch64-apple-darwin/release/kanata").path,
            projectRoot.appendingPathComponent("External/kanata/target/release/kanata").path
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw XCTSkip("""
        Kanata binary not found - skipping real validation test.
        Searched: \(candidates.joined(separator: ", "))
        """)
    }

    private func validateCatalogConfig(withBinary kanataBinary: String) async throws {
        // Generate config from the ACTUAL default catalog
        let catalog = RuleCollectionCatalog()
        let defaultCollections = catalog.defaultCollections()
        let configContent = KanataConfiguration.generateFromCollections(defaultCollections)

        // Write to temp file
        let tempPath = tempDirectory.appendingPathComponent("catalog_validation_test.kbd")
        try configContent.write(to: tempPath, atomically: true, encoding: .utf8)

        // Validate with kanata --check
        let process = Process()
        process.executableURL = URL(fileURLWithPath: kanataBinary)
        process.arguments = ["--cfg", tempPath.path, "--check"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempPath)

        // Assert config is valid
        if process.terminationStatus != 0 {
            // Include the generated config in the failure message for debugging
            let configPreview = String(configContent.prefix(2000))
            XCTFail("""
            Default catalog generates INVALID Kanata config!

            Exit code: \(process.terminationStatus)

            Kanata output:
            \(output)
            \(errorOutput)

            Generated config (first 2000 chars):
            \(configPreview)

            This means a change to RuleCollectionCatalog or config generation
            introduced a syntax error. Fix the catalog mappings or generation logic.
            """)
        }

        // Verify we got the expected success message
        XCTAssertTrue(
            output.contains("config file is valid") || errorOutput.contains("config file is valid"),
            "Kanata should confirm config is valid"
        )
    }

    func testRoundTrip_GenerateParseGenerate() throws {
        let originalMappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "a", output: "b")
        ]

        // Generate config
        let generatedConfig = KanataConfiguration.generateFromMappings(originalMappings)

        // Parse it back
        let parsed = try configService.parseConfigurationFromString(generatedConfig)

        // Verify original mappings are preserved (system defaults may add more)
        for original in originalMappings {
            let found = parsed.keyMappings.first { $0.input == original.input }
            XCTAssertNotNil(found, "Should find mapping for \(original.input)")
            XCTAssertEqual(found?.output, original.output, "Output should match for \(original.input)")
        }
        XCTAssertGreaterThanOrEqual(
            parsed.keyMappings.count, originalMappings.count,
            "Generated config should not drop mappings (may include system defaults)"
        )
    }

    // MARK: - Config Write Safety Guard Tests

    /// Test that generated config is never empty when using generateFromMappings
    func testGenerateFromMappings_NeverProducesEmptyConfig() {
        // Even with empty mappings, we should get a valid config with system defaults
        let config = KanataConfiguration.generateFromMappings([])

        XCTAssertFalse(config.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "Generated config should never be empty")
        XCTAssertTrue(config.contains("defsrc"), "Generated config should have defsrc")
        XCTAssertTrue(config.contains("deflayer"), "Generated config should have deflayer")
    }

    /// Test that generated config from collections is never empty
    func testGenerateFromCollections_NeverProducesEmptyConfig() {
        // Even with no enabled collections, we should get a valid config
        let disabledCollection = RuleCollection(
            name: "Disabled",
            summary: "All disabled",
            category: .custom,
            mappings: [KeyMapping(input: "a", output: "b")],
            isEnabled: false
        )

        let config = KanataConfiguration.generateFromCollections([disabledCollection])

        XCTAssertFalse(config.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "Generated config should never be empty")
        XCTAssertTrue(config.contains("defsrc"), "Generated config should have defsrc")
        XCTAssertTrue(config.contains("deflayer"), "Generated config should have deflayer")
    }

    /// Test that saveConfiguration succeeds with valid content
    func testSaveConfiguration_ValidContentSucceeds() async throws {
        let mappings = [KeyMapping(input: "caps", output: "esc")]

        // Should not throw
        try await configService.saveConfiguration(keyMappings: mappings)

        // Verify file was created with valid structure
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        let content = try String(contentsOf: configPath, encoding: .utf8)
        XCTAssertTrue(content.contains("defsrc"), "Saved config should have defsrc")
        XCTAssertTrue(content.contains("deflayer"), "Saved config should have deflayer")
        XCTAssertFalse(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "Saved config should not be empty")
    }

    /// Test that writeConfigurationContent rejects empty content
    func testWriteConfigurationContent_RejectsEmptyContent() async throws {
        // Try to write empty content directly
        do {
            try await configService.writeConfigurationContent("")
            XCTFail("writeConfigurationContent should throw for empty content")
        } catch let error as KeyPathError {
            if case let .configuration(configError) = error,
               case let .invalidFormat(reason) = configError {
                XCTAssertTrue(reason.contains("empty"), "Error should mention empty content")
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    /// Test that writeConfigurationContent rejects invalid structure
    func testWriteConfigurationContent_RejectsInvalidStructure() async throws {
        // Try to write config missing required structure
        // IMPORTANT: Do not mention "defsrc" or "deflayer" in comments
        // as the guard checks for substring presence
        let invalidContent = """
        (defcfg
          process-unmapped-keys yes
        )
        ;; This config is missing required blocks - it is invalid
        """

        do {
            try await configService.writeConfigurationContent(invalidContent)
            XCTFail("writeConfigurationContent should throw for invalid structure")
        } catch let error as KeyPathError {
            if case let .configuration(configError) = error,
               case let .invalidFormat(reason) = configError {
                XCTAssertTrue(reason.contains("defsrc") || reason.contains("deflayer"),
                              "Error should mention missing defsrc/deflayer")
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    /// Test that writeConfigurationContent accepts valid content
    func testWriteConfigurationContent_AcceptsValidContent() async throws {
        let validContent = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc caps)
        (deflayer base esc)
        """

        // Should not throw
        try await configService.writeConfigurationContent(validContent)

        // Verify file was created with correct content
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        let written = try String(contentsOf: configPath, encoding: .utf8)
        XCTAssertEqual(written, validContent, "Written content should match input")
    }

    // MARK: - Observer/Notification Tests

    func testObserverFiresOnMainActor_OnSave() async throws {
        let exp = expectation(description: "Observer fired on save")
        actor Flag {
            var value = false
            func setTrue() { value = true }
            func get() -> Bool { value }
        }
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
        actor Flag {
            var value = false
            func setTrue() { value = true }
            func get() -> Bool { value }
        }
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

    func testReloadCreatesDefaultConfigWhenMissing() async throws {
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        try? FileManager.default.removeItem(at: configPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configPath.path))

        let config = try await configService.reload()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: configPath.path),
            "Reload should create default config when missing"
        )
        XCTAssertFalse(config.content.isEmpty, "Default config content should not be empty")
    }
}

private extension ConfigurationServiceTests {
    func extractLayer(named name: String, from config: String) -> String {
        let marker = "(deflayer \(name)"
        guard let start = config.range(of: marker) else { return "" }
        let suffix = config[start.lowerBound...]
        if let end = suffix.range(of: "\n)\n") {
            return String(suffix[..<end.upperBound])
        } else if let finalEnd = suffix.range(of: "\n)\r") {
            return String(suffix[..<finalEnd.upperBound])
        } else {
            return String(suffix)
        }
    }
}
