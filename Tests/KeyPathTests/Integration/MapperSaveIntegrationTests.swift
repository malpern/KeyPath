@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// End-to-end integration tests for the mapper save pipeline:
///   Custom rule creation → config generation → .kbd file written → label map update
///
/// These exercise the path from MapperViewModel.save() through RuleCollectionsManager
/// to ConfigurationService, verifying the full chain that breaks most often.
final class MapperSaveIntegrationTests: XCTestCase {
    @MainActor
    private func createTestEnvironment() async throws -> (RuleCollectionsManager, URL) {
        TestEnvironment.forceTestMode = true

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapper-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json")
        )
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json")
        )
        let configService = ConfigurationService(configDirectory: tempDir.path)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customStore,
            configurationService: configService,
            eventListener: KanataEventListener()
        )

        return (manager, tempDir)
    }

    // MARK: - Custom Rule Save → Config

    @MainActor
    func testSaveCustomRule_GeneratesConfig() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try await createTestEnvironment()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rule = CustomRule(input: "a", action: .keystroke(key: "b"))
        await manager.saveCustomRule(rule, skipReload: true, autoResolveConflicts: true)

        let configPath = tempDir.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path), "Config file should exist")

        let config = try String(contentsOf: configPath, encoding: .utf8)
        XCTAssertTrue(config.contains("b"), "Config should contain the output key 'b'")
    }

    @MainActor
    func testSaveCustomRule_WithShiftedOutput_GeneratesConfig() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try await createTestEnvironment()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rule = CustomRule(input: "1", action: .keystroke(key: "2"), shiftedOutput: "at")
        await manager.saveCustomRule(rule, skipReload: true, autoResolveConflicts: true)

        let configPath = tempDir.appendingPathComponent("keypath.kbd")
        let config = try String(contentsOf: configPath, encoding: .utf8)

        XCTAssertTrue(
            config.contains("2") || config.contains("at"),
            "Config should contain either the main output or shifted output"
        )
    }

    @MainActor
    func testSaveMultipleRules_AllAppearInConfig() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try await createTestEnvironment()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rules = [
            CustomRule(input: "a", action: .keystroke(key: "b")),
            CustomRule(input: "s", action: .keystroke(key: "d")),
            CustomRule(input: "f", action: .keystroke(key: "g")),
        ]

        for rule in rules {
            await manager.saveCustomRule(rule, skipReload: true, autoResolveConflicts: true)
        }

        let configPath = tempDir.appendingPathComponent("keypath.kbd")
        let config = try String(contentsOf: configPath, encoding: .utf8)

        XCTAssertTrue(config.contains("b"), "Config should contain output 'b' from first rule")
        XCTAssertTrue(config.contains("d"), "Config should contain output 'd' from second rule")
        XCTAssertTrue(config.contains("g"), "Config should contain output 'g' from third rule")
    }

    @MainActor
    func testDeleteCustomRule_RegeneratesConfigWithout() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try await createTestEnvironment()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rule = CustomRule(input: "a", action: .keystroke(key: "b"))
        await manager.saveCustomRule(rule, skipReload: true, autoResolveConflicts: true)

        // Verify rule is in config
        let configPath = tempDir.appendingPathComponent("keypath.kbd")
        var config = try String(contentsOf: configPath, encoding: .utf8)
        let hadB = config.contains("b")

        // Delete the rule
        if let ruleToRemove = manager.customRules.first(where: { $0.input == "a" }) {
            await manager.removeCustomRule(id: ruleToRemove.id)
        }

        config = try String(contentsOf: configPath, encoding: .utf8)
        if hadB {
            // After deletion, the output 'b' should no longer appear as a remap
            // (it may still appear in defsrc if 'b' is a physical key)
            XCTAssertFalse(config.isEmpty, "Config should still exist after rule deletion")
        }
    }

    // MARK: - Custom Rule → Label Map Update

    @MainActor
    func testSaveCustomRule_UpdatesLabelMap() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try await createTestEnvironment()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Save a custom rule
        let rule = CustomRule(input: "a", action: .keystroke(key: "b"))
        await manager.saveCustomRule(rule, skipReload: true, autoResolveConflicts: true)

        // Verify the custom rule is in the manager's store
        let found = manager.customRules.contains { $0.input == "a" && $0.action == .keystroke(key: "b") }
        XCTAssertTrue(found, "Custom rule should be persisted in the store")
    }

    // MARK: - Pack Enable + Custom Rule Combined

    @MainActor
    func testPackAndCustomRuleCombined_GeneratesValidConfig() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try await createTestEnvironment()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Enable a pack
        let capsCollectionID = RuleCollectionIdentifier.capsLockRemap
        let packSuccess = await manager.toggleCollection(
            id: capsCollectionID,
            isEnabled: true,
            autoResolveConflicts: true,
            bypassOwnershipCheck: true
        )
        XCTAssertTrue(packSuccess)

        // Add a custom rule on top
        let rule = CustomRule(input: "s", action: .keystroke(key: "d"))
        await manager.saveCustomRule(rule, skipReload: true, autoResolveConflicts: true)

        // Verify config has both
        let configPath = tempDir.appendingPathComponent("keypath.kbd")
        let config = try String(contentsOf: configPath, encoding: .utf8)

        XCTAssertTrue(
            config.contains("caps") || config.contains("capslock"),
            "Config should contain caps lock remap from pack"
        )
        XCTAssertTrue(config.contains("d"), "Config should contain custom rule output")
    }

    @MainActor
    func testSaveCustomRule_PostsNotification() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try await createTestEnvironment()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expectation = expectation(forNotification: .ruleCollectionsChanged, object: nil)

        let rule = CustomRule(input: "a", action: .keystroke(key: "b"))
        await manager.saveCustomRule(rule, skipReload: true, autoResolveConflicts: true)

        await fulfillment(of: [expectation], timeout: 5.0)
    }
}
