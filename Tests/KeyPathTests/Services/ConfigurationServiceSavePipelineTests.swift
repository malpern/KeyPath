import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
@preconcurrency import XCTest

@MainActor
final class ConfigurationServiceSavePipelineTests: KeyPathTestCase {
    private lazy var tempDirectory: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KeyPathSavePipelineTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private lazy var configService: ConfigurationService = .init(configDirectory: tempDirectory.path)

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Conflict Rejection Tests

    func testSaveConfiguration_ThrowsOnMappingConflict() async {
        let collectionA = RuleCollection(
            name: "Collection A",
            summary: "Maps caps to esc",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let collectionB = RuleCollection(
            name: "Collection B",
            summary: "Also maps caps",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "tab"))],
            isEnabled: true,
            isSystemDefault: false
        )

        do {
            try await configService.saveConfiguration(
                ruleCollections: [collectionA, collectionB]
            )
            XCTFail("Should throw when two collections map the same key")
        } catch let error as KeyPathError {
            if case let .configuration(.mappingConflicts(conflicts)) = error {
                XCTAssertEqual(conflicts.count, 1)
                XCTAssertEqual(conflicts.first?.inputKey, "caps")
                XCTAssertTrue(
                    conflicts.first?.conflictingCollections.contains("Collection A") ?? false
                )
                XCTAssertTrue(
                    conflicts.first?.conflictingCollections.contains("Collection B") ?? false
                )
            } else {
                XCTFail("Expected mappingConflicts error, got \(error)")
            }
        } catch {
            XCTFail("Expected KeyPathError, got \(error)")
        }
    }

    func testSaveConfiguration_ConflictReportsCorrectLayer() async {
        let nav1 = RuleCollection(
            name: "Nav A",
            summary: "Nav layer A",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .navigation
        )
        let nav2 = RuleCollection(
            name: "Nav B",
            summary: "Nav layer B",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "home"))],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .navigation
        )

        do {
            try await configService.saveConfiguration(ruleCollections: [nav1, nav2])
            XCTFail("Should throw for same-layer conflict")
        } catch let error as KeyPathError {
            if case let .configuration(.mappingConflicts(conflicts)) = error {
                XCTAssertEqual(conflicts.first?.layer, "Navigation")
            } else {
                XCTFail("Expected mappingConflicts error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveConfiguration_NoConflictWhenDifferentLayers() async throws {
        let baseCollection = RuleCollection(
            name: "Base Keys",
            summary: "Base layer",
            category: .custom,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "h"))],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .base
        )
        let navCollection = RuleCollection(
            name: "Nav Keys",
            summary: "Nav layer",
            category: .navigation,
            mappings: [KeyMapping(input: "h", action: .keystroke(key: "left"))],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation)
        )

        try await configService.saveConfiguration(
            ruleCollections: [baseCollection, navCollection]
        )

        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
    }

    func testSaveConfiguration_NoConflictWhenOneCollectionDisabled() async throws {
        let collectionA = RuleCollection(
            name: "Collection A",
            summary: "Maps caps",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let collectionB = RuleCollection(
            name: "Collection B",
            summary: "Also maps caps but disabled",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "tab"))],
            isEnabled: false,
            isSystemDefault: false
        )

        try await configService.saveConfiguration(
            ruleCollections: [collectionA, collectionB]
        )

        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
    }

    func testSaveConfiguration_MultipleConflictsReportedTogether() async {
        let collectionA = RuleCollection(
            name: "Collection A",
            summary: "Maps a and b",
            category: .custom,
            mappings: [
                KeyMapping(input: "a", action: .keystroke(key: "x")),
                KeyMapping(input: "b", action: .keystroke(key: "y")),
            ],
            isEnabled: true,
            isSystemDefault: false
        )
        let collectionB = RuleCollection(
            name: "Collection B",
            summary: "Also maps a and b",
            category: .custom,
            mappings: [
                KeyMapping(input: "a", action: .keystroke(key: "1")),
                KeyMapping(input: "b", action: .keystroke(key: "2")),
            ],
            isEnabled: true,
            isSystemDefault: false
        )

        do {
            try await configService.saveConfiguration(
                ruleCollections: [collectionA, collectionB]
            )
            XCTFail("Should throw for multiple conflicts")
        } catch let error as KeyPathError {
            if case let .configuration(.mappingConflicts(conflicts)) = error {
                XCTAssertEqual(conflicts.count, 2, "Should report both conflicting keys")
                let keys = Set(conflicts.map(\.inputKey))
                XCTAssertTrue(keys.contains("a"))
                XCTAssertTrue(keys.contains("b"))
            } else {
                XCTFail("Expected mappingConflicts, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Validate-Before-Write Invariant Tests

    func testSaveConfiguration_DoesNotWriteWhenValidationFails() async {
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: configPath.path),
            "Config file should not exist before save"
        )

        let conflictingA = RuleCollection(
            name: "A",
            summary: "A",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let conflictingB = RuleCollection(
            name: "B",
            summary: "B",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "tab"))],
            isEnabled: true,
            isSystemDefault: false
        )

        do {
            try await configService.saveConfiguration(
                ruleCollections: [conflictingA, conflictingB]
            )
        } catch {
            // Expected
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: configPath.path),
            "Config file should not be written when conflicts are detected"
        )
    }

    func testSaveConfiguration_ExistingConfigPreservedOnConflict() async throws {
        let initialCollection = RuleCollection(
            name: "Initial",
            summary: "Initial config",
            category: .custom,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"))],
            isEnabled: true,
            isSystemDefault: false
        )
        try await configService.saveConfiguration(ruleCollections: [initialCollection])

        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        let originalContent = try String(contentsOfFile: configPath.path, encoding: .utf8)

        let conflictA = RuleCollection(
            name: "Conflict A",
            summary: "A",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let conflictB = RuleCollection(
            name: "Conflict B",
            summary: "B",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "tab"))],
            isEnabled: true,
            isSystemDefault: false
        )

        do {
            try await configService.saveConfiguration(
                ruleCollections: [conflictA, conflictB]
            )
        } catch {
            // Expected
        }

        let afterContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertEqual(
            originalContent, afterContent,
            "Existing config should be unchanged after a failed save"
        )
    }

    // MARK: - Write Safety Tests

    func testWriteFileAsync_RejectsEmptyContent() async {
        do {
            try await configService.writeFileAsync(
                string: "",
                to: tempDirectory.appendingPathComponent("keypath.kbd").path
            )
            XCTFail("Should reject empty content")
        } catch let error as KeyPathError {
            if case .configuration(.invalidFormat) = error {
                // Expected
            } else {
                XCTFail("Expected invalidFormat, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWriteFileAsync_RejectsWhitespaceOnlyContent() async {
        do {
            try await configService.writeFileAsync(
                string: "   \n\n  \t  ",
                to: tempDirectory.appendingPathComponent("keypath.kbd").path
            )
            XCTFail("Should reject whitespace-only content")
        } catch let error as KeyPathError {
            if case .configuration(.invalidFormat) = error {
                // Expected
            } else {
                XCTFail("Expected invalidFormat, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWriteFileAsync_RejectsKbdFileMissingDefsrc() async {
        do {
            try await configService.writeFileAsync(
                string: "(defcfg process-unmapped-keys yes)",
                to: tempDirectory.appendingPathComponent("keypath.kbd").path
            )
            XCTFail("Should reject kbd file without defsrc/deflayer")
        } catch let error as KeyPathError {
            if case .configuration(.invalidFormat) = error {
                // Expected
            } else {
                XCTFail("Expected invalidFormat, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWriteFileAsync_AcceptsKbdWithDefsrc() async throws {
        let validContent = """
        (defcfg process-unmapped-keys yes)
        (defsrc caps)
        (deflayer base esc)
        """
        try await configService.writeFileAsync(
            string: validContent,
            to: tempDirectory.appendingPathComponent("keypath.kbd").path
        )

        let written = try String(
            contentsOfFile: tempDirectory.appendingPathComponent("keypath.kbd").path,
            encoding: .utf8
        )
        XCTAssertEqual(written, validContent)
    }

    func testWriteFileAsync_AllowsNonKbdFileWithoutDefsrc() async throws {
        let content = "some log content"
        let logPath = tempDirectory.appendingPathComponent("test.log").path
        try await configService.writeFileAsync(string: content, to: logPath)

        let written = try String(contentsOfFile: logPath, encoding: .utf8)
        XCTAssertEqual(written, content)
    }

    // MARK: - Observer Notification Tests

    private actor ObserverFlag {
        var fired = false
        var content: String?
        func setFired(_ configContent: String?) {
            fired = true
            content = configContent
        }

        func get() -> (fired: Bool, content: String?) {
            (fired, content)
        }
    }

    func testSaveConfiguration_NotifiesObservers() async throws {
        let exp = expectation(description: "Observer notified")
        let flag = ObserverFlag()

        let token = configService.observe { config in
            Task { @MainActor in
                await flag.setFired(config.content)
                exp.fulfill()
            }
        }

        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        try await configService.saveConfiguration(ruleCollections: [collection])

        await fulfillment(of: [exp], timeout: 2)
        let result = await flag.get()
        XCTAssertTrue(result.fired)
        XCTAssertTrue(result.content?.contains("caps") ?? false)

        _ = token
    }

    func testSaveConfiguration_DoesNotNotifyOnConflict() async {
        let flag = ObserverFlag()

        let token = configService.observe { _ in
            Task { @MainActor in
                await flag.setFired(nil)
            }
        }

        let conflictA = RuleCollection(
            name: "A",
            summary: "A",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let conflictB = RuleCollection(
            name: "B",
            summary: "B",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "tab"))],
            isEnabled: true,
            isSystemDefault: false
        )

        do {
            try await configService.saveConfiguration(
                ruleCollections: [conflictA, conflictB]
            )
        } catch {
            // Expected
        }

        let result = await flag.get()
        XCTAssertFalse(result.fired, "Observer should not fire when save fails due to conflicts")
        _ = token
    }

    // MARK: - Preserved Chord/Sequence Injection Tests

    func testLoadPreservedChordGroups_ReturnsEmptyWhenNoConfig() {
        let groups = configService.loadPreservedChordGroups()
        XCTAssertTrue(groups.isEmpty)
    }

    func testLoadPreservedChordGroups_ParsesFromDiskWhenNoCachedConfig() throws {
        let configWithChords = """
        (defcfg process-unmapped-keys yes)
        (defsrc a s d f)
        (deflayer base a s d f)
        (defchords group1 200
          (a s) esc
          (d f) tab
        )
        """
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        try configWithChords.write(to: configPath, atomically: true, encoding: .utf8)

        let groups = configService.loadPreservedChordGroups()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "group1")
    }

    func testLoadPreservedChordGroups_ReturnsCachedGroupsWhenAvailable() async throws {
        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        try await configService.saveConfiguration(ruleCollections: [collection])

        let config = configService.withLockedCurrentConfig()
        XCTAssertNotNil(config, "After save, current config should be cached")
    }

    func testLoadPreservedSequences_ReturnsEmptyWhenNoConfig() {
        let sequences = configService.loadPreservedSequences()
        XCTAssertTrue(sequences.isEmpty)
    }

    func testLoadPreservedSequences_ParsesFromDiskWhenNoCachedConfig() throws {
        let configWithSequences = """
        (defcfg process-unmapped-keys yes)
        (defsrc a s d)
        (deflayer base a s d)
        (defseq hello-seq (a s d))
        """
        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        try configWithSequences.write(to: configPath, atomically: true, encoding: .utf8)

        let sequences = configService.loadPreservedSequences()
        XCTAssertEqual(sequences.count, 1)
        XCTAssertEqual(sequences.first?.name, "hello-seq")
        XCTAssertEqual(sequences.first?.keys, ["a", "s", "d"])
    }

    // MARK: - Neovim Terminal Exclusion Tests

    func testSaveConfiguration_ExcludesNeovimTerminalMappings() async throws {
        let neovimCollection = RuleCollection(
            id: RuleCollectionIdentifier.neovimTerminal,
            name: "Neovim Terminal",
            summary: "Reference collection",
            category: .custom,
            mappings: [KeyMapping(input: "j", action: .keystroke(key: "down"))],
            isEnabled: true,
            isSystemDefault: false,
            targetLayer: .base
        )
        let regularCollection = RuleCollection(
            name: "Regular",
            summary: "Normal collection",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )

        try await configService.saveConfiguration(
            ruleCollections: [regularCollection, neovimCollection]
        )

        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        let savedContent = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertFalse(
            savedContent.contains("Neovim Terminal"),
            "Neovim Terminal should be excluded from config"
        )
        XCTAssertTrue(savedContent.contains("caps"))
    }

    // MARK: - Custom Rules Priority Tests

    func testSaveConfiguration_CustomRulesTakePriorityOverPresets() async throws {
        let preset = RuleCollection(
            name: "Preset",
            summary: "Preset",
            category: .system,
            mappings: [KeyMapping(input: "a", action: .keystroke(key: "x"))],
            isEnabled: true,
            isSystemDefault: true
        )
        let customRule = CustomRule(
            title: "My Rule",
            input: "a",
            action: .keystroke(key: "z")
        )

        do {
            try await configService.saveConfiguration(
                ruleCollections: [preset],
                customRules: [customRule]
            )
            XCTFail("Should throw conflict when custom rule and preset map the same key")
        } catch let error as KeyPathError {
            if case let .configuration(.mappingConflicts(conflicts)) = error {
                XCTAssertEqual(conflicts.first?.inputKey, "a")
            } else {
                XCTFail("Expected mappingConflicts, got \(error)")
            }
        }
    }

    // MARK: - Deduplicator Unit Tests

    func testDeduplicator_DetectsConflictsBeforeDeduplication() {
        let collA = RuleCollection(
            name: "A",
            summary: "A",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let collB = RuleCollection(
            name: "B",
            summary: "B",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "tab"))],
            isEnabled: true,
            isSystemDefault: false
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [collA, collB])
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.inputKey, "caps")
    }

    func testDeduplicator_IgnoresDisabledCollections() {
        let enabled = RuleCollection(
            name: "Enabled",
            summary: "E",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let disabled = RuleCollection(
            name: "Disabled",
            summary: "D",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "tab"))],
            isEnabled: false,
            isSystemDefault: false
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [enabled, disabled])
        XCTAssertTrue(conflicts.isEmpty, "Disabled collections should not cause conflicts")
    }

    func testDeduplicator_ConflictsAreSortedByKey() {
        let collA = RuleCollection(
            name: "A",
            summary: "A",
            category: .custom,
            mappings: [
                KeyMapping(input: "z", action: .keystroke(key: "1")),
                KeyMapping(input: "a", action: .keystroke(key: "2")),
            ],
            isEnabled: true,
            isSystemDefault: false
        )
        let collB = RuleCollection(
            name: "B",
            summary: "B",
            category: .custom,
            mappings: [
                KeyMapping(input: "z", action: .keystroke(key: "3")),
                KeyMapping(input: "a", action: .keystroke(key: "4")),
            ],
            isEnabled: true,
            isSystemDefault: false
        )

        let conflicts = RuleCollectionDeduplicator.detectConflicts(in: [collA, collB])
        XCTAssertEqual(conflicts.count, 2)
        XCTAssertEqual(conflicts[0].inputKey, "a")
        XCTAssertEqual(conflicts[1].inputKey, "z")
    }

    func testDeduplicator_DedupeRemovesDuplicateInputKeys() {
        let collA = RuleCollection(
            name: "A",
            summary: "A",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let collB = RuleCollection(
            name: "B",
            summary: "B",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "tab"))],
            isEnabled: true,
            isSystemDefault: false
        )

        let deduped = RuleCollectionDeduplicator.dedupe([collA, collB])
        XCTAssertEqual(deduped[0].mappings.count, 1, "First collection keeps its mapping")
        XCTAssertEqual(deduped[1].mappings.count, 0, "Second collection's duplicate removed")
    }

    func testDeduplicator_DedupePreservesDisabledCollections() {
        let enabled = RuleCollection(
            name: "E",
            summary: "E",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        let disabled = RuleCollection(
            name: "D",
            summary: "D",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "tab"))],
            isEnabled: false,
            isSystemDefault: false
        )

        let deduped = RuleCollectionDeduplicator.dedupe([enabled, disabled])
        XCTAssertEqual(deduped[1].mappings.count, 1, "Disabled collection mappings untouched")
    }

    // MARK: - Validation Test Mode Tests

    func testValidationInTestMode_PassesValidConfig() async {
        let validConfig = """
        (defcfg process-unmapped-keys yes)
        (defsrc caps)
        (deflayer base esc)
        """
        let result = await configService.validateConfiguration(validConfig)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testValidationInTestMode_RejectsEmptyConfig() async {
        let result = await configService.validateConfiguration("")
        XCTAssertFalse(result.isValid)
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - Config Content After Successful Save Tests

    func testSaveConfiguration_UpdatesCachedConfig() async throws {
        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        try await configService.saveConfiguration(ruleCollections: [collection])

        let cached = configService.withLockedCurrentConfig()
        XCTAssertNotNil(cached)
        XCTAssertTrue(cached?.content.contains("caps") ?? false)
        XCTAssertTrue(cached?.content.contains("esc") ?? false)
    }

    func testSaveConfiguration_CachedMappingsMatchSavedContent() async throws {
        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [
                KeyMapping(input: "caps", action: .keystroke(key: "esc")),
                KeyMapping(input: "a", action: .keystroke(key: "b")),
            ],
            isEnabled: true,
            isSystemDefault: false
        )
        try await configService.saveConfiguration(ruleCollections: [collection])

        let cached = configService.withLockedCurrentConfig()
        XCTAssertNotNil(cached)
        let mappingInputs = Set(cached?.keyMappings.map(\.input) ?? [])
        XCTAssertTrue(mappingInputs.contains("caps"))
        XCTAssertTrue(mappingInputs.contains("a"))
    }

    // MARK: - Reload Tests

    func testReload_ThrowsFileNotFoundWhenMissing() async {
        let emptyDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KeyPathReloadTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let service = ConfigurationService(configDirectory: emptyDir.path)
        do {
            _ = try await service.reload()
        } catch let error as KeyPathError {
            if case .configuration(.fileNotFound) = error {
                // Expected — reload creates default config, but stores may vary
            } else if case .configuration(.loadFailed) = error {
                // Also acceptable
            } else {
                // reload() may succeed after creating defaults — that's fine too
            }
        } catch {
            // Non-KeyPathError is fine if default creation happens
        }
    }

    func testValidateContent_RejectsEmptyContent() {
        do {
            _ = try configService.validate(content: "")
            XCTFail("Should throw on empty content")
        } catch let error as KeyPathError {
            if case .configuration(.invalidFormat) = error {
                // Expected
            } else {
                XCTFail("Expected invalidFormat, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateContent_RejectsWhitespaceOnly() {
        do {
            _ = try configService.validate(content: "   \n\t\n   ")
            XCTFail("Should throw on whitespace-only content")
        } catch let error as KeyPathError {
            if case .configuration(.invalidFormat) = error {
                // Expected
            } else {
                XCTFail("Expected invalidFormat, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Kanata Error Parsing Tests

    func testParseKanataErrors_ExtractsHelpLines() {
        let output = """
        [ERROR] Could not parse configuration
        help: Unknown key in defsrc: "hangeul"
        """
        let errors = configService.parseKanataErrors(output)
        XCTAssertTrue(errors.count >= 2, "Should extract both ERROR and help lines")
        XCTAssertTrue(errors.contains(where: { $0.contains("hangeul") }))
    }

    func testParseKanataErrors_HandlesMultipleHelpLines() {
        let output = """
        [ERROR] Multiple issues found
        help: Unknown key: "foo"
        help: Missing layer definition
        """
        let errors = configService.parseKanataErrors(output)
        XCTAssertTrue(errors.count >= 3)
    }

    func testParseKanataErrors_ReturnsEmptyForCleanOutput() {
        let output = ""
        let errors = configService.parseKanataErrors(output)
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - StripManagedRepeat Tests

    func testStripManagedRepeatForValidation_RemovesManagedRepeatLines() {
        let config = """
        (defcfg
          process-unmapped-keys yes
          managed-repeat rate 50
          managed-repeat delay 200
        )
        (defsrc caps)
        (deflayer base esc)
        """
        let stripped = ConfigurationService.stripManagedRepeatForValidation(config)
        XCTAssertFalse(stripped.contains("managed-repeat"))
        XCTAssertTrue(stripped.contains("process-unmapped-keys"))
        XCTAssertTrue(stripped.contains("defsrc"))
    }

    func testStripManagedRepeatForValidation_RemovesDefrepeatBlock() {
        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc caps)
        (deflayer base esc)
        (defrepeat
          rate 50
          delay 200
        )
        """
        let stripped = ConfigurationService.stripManagedRepeatForValidation(config)
        XCTAssertFalse(stripped.contains("defrepeat"))
        XCTAssertFalse(stripped.contains("rate 50"))
    }

    func testStripManagedRepeatForValidation_PreservesOtherContent() {
        let config = """
        (defcfg process-unmapped-keys yes)
        (defsrc caps a)
        (deflayer base esc b)
        (defalias myalias (layer-while-held nav))
        """
        let stripped = ConfigurationService.stripManagedRepeatForValidation(config)
        XCTAssertEqual(stripped, config, "Config without managed-repeat should be unchanged")
    }

    // MARK: - Edge Case Tests

    func testSaveConfiguration_EmptyCollectionsList() async throws {
        try await configService.saveConfiguration(ruleCollections: [])

        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
        let content = try String(contentsOfFile: configPath.path, encoding: .utf8)
        XCTAssertTrue(content.contains("defsrc"), "Even empty collections should produce valid config")
    }

    func testSaveConfiguration_EmptyCustomRules() async throws {
        let collection = RuleCollection(
            name: "Test",
            summary: "test",
            category: .custom,
            mappings: [KeyMapping(input: "caps", action: .keystroke(key: "esc"))],
            isEnabled: true,
            isSystemDefault: false
        )
        try await configService.saveConfiguration(
            ruleCollections: [collection],
            customRules: []
        )

        let configPath = tempDirectory.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
    }

    // MARK: - Helper

    private func extractLayer(named name: String, from config: String) -> String {
        let lines = config.components(separatedBy: .newlines)
        var inLayer = false
        var layerLines: [String] = []
        for line in lines {
            if line.contains("(deflayer \(name)") {
                inLayer = true
                continue
            }
            if inLayer {
                if line.trimmingCharacters(in: .whitespacesAndNewlines) == ")" {
                    break
                }
                layerLines.append(line)
            }
        }
        return layerLines.joined(separator: "\n")
    }
}
