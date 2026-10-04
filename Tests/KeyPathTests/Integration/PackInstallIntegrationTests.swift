@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// End-to-end integration test: pack install → config generation → label map update.
///
/// This exercises the full pipeline that's documented in CLAUDE.md's data flow section.
/// Uses real code at every layer except the system boundary (no launchctl, no TCP).
/// The test creates a temp directory, installs a pack, and verifies:
/// 1. The rule collection is enabled
/// 2. A valid .kbd config file is generated with the expected content
/// 3. The KeyboardVisualizationViewModel picks up the change and updates its label map
final class PackInstallIntegrationTests: XCTestCase {
    @MainActor
    func testHomeRowModsPackInstall_GeneratesConfigAndUpdatesLabels() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        // --- Setup: temp directory and services ---
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pack-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json")
        )
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json")
        )
        let configService = ConfigurationService.sessionTestService(configDirectory: tempDir.path, ruleCollectionStore: collectionStore, customRulesStore: customStore)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customStore,
            configurationService: configService,
            eventListener: KanataEventListener()
        )

        // --- Act: enable the Home Row Mods collection (same as pack install) ---
        let collectionID = RuleCollectionIdentifier.homeRowMods
        let success = await manager.toggleCollection(
            id: collectionID,
            isEnabled: true,
            autoResolveConflicts: true,
            bypassOwnershipCheck: true
        )
        XCTAssertTrue(success, "toggleCollection should succeed")

        // --- Assert 1: Collection is enabled in the store ---
        let collections = await collectionStore.loadCollections()
        let collection = collections.first { $0.id == collectionID }
        XCTAssertNotNil(collection, "Home Row Mods collection should exist in store")
        XCTAssertTrue(collection?.isEnabled ?? false, "Collection should be enabled")

        // --- Assert 2: Config file was generated ---
        let configPath = tempDir.appendingPathComponent("keypath.kbd")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: configPath.path),
            "Config file should be written to \(configPath.path)"
        )

        let configContent = try String(contentsOf: configPath, encoding: .utf8)
        XCTAssertFalse(configContent.isEmpty, "Config should not be empty")

        XCTAssertTrue(configContent.contains("tap-hold"), "Home-row pack should generate tap/hold actions")
        let vm = KeyboardVisualizationViewModel()
        vm.updateTapHoldIdleLabels(from: collections)
        XCTAssertNotNil(vm.tapHoldIdleLabels[0], "A should have an idle tap label after install")
    }

    @MainActor
    func testPackInstall_NotificationPosted() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pack-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json")
        )
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json")
        )
        let configService = ConfigurationService.sessionTestService(configDirectory: tempDir.path, ruleCollectionStore: collectionStore, customRulesStore: customStore)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customStore,
            configurationService: configService,
            eventListener: KanataEventListener()
        )

        // Listen for the notification
        let expectation = expectation(forNotification: .ruleCollectionsChanged, object: nil)

        let collectionID = RuleCollectionIdentifier.homeRowMods
        let success = await manager.toggleCollection(
            id: collectionID,
            isEnabled: true,
            autoResolveConflicts: true,
            bypassOwnershipCheck: true
        )
        XCTAssertTrue(success)

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    @MainActor
    func testVimNavPackInstall_GeneratesLayerConfig() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pack-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json")
        )
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json")
        )
        let configService = ConfigurationService.sessionTestService(configDirectory: tempDir.path, ruleCollectionStore: collectionStore, customRulesStore: customStore)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customStore,
            configurationService: configService,
            eventListener: KanataEventListener()
        )

        // Find the vim navigation collection
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.vim-navigation"),
              let collectionID = pack.associatedCollectionID
        else {
            return XCTFail("Vim navigation pack not found")
        }

        let success = await manager.toggleCollection(
            id: collectionID,
            isEnabled: true,
            autoResolveConflicts: true,
            bypassOwnershipCheck: true
        )
        XCTAssertTrue(success)

        // Verify config contains vim navigation layer content (h/j/k/l → arrows)
        let configPath = tempDir.appendingPathComponent("keypath.kbd")
        let configContent = try String(contentsOf: configPath, encoding: .utf8)

        // Vim nav maps h→left, j→down, k→up, l→right on a nav layer
        XCTAssertTrue(
            configContent.contains("left") && configContent.contains("down") &&
                configContent.contains("up") && configContent.contains("right"),
            "Config should contain arrow key mappings from vim navigation"
        )
        XCTAssertTrue(
            configContent.contains("nav") || configContent.contains("deflayer"),
            "Config should contain a layer definition"
        )
    }

    @MainActor
    func testPackUninstall_RegeneratesConfigWithout() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pack-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let collectionStore = RuleCollectionStore(
            fileURL: tempDir.appendingPathComponent("RuleCollections.json")
        )
        let customStore = CustomRulesStore(
            fileURL: tempDir.appendingPathComponent("CustomRules.json")
        )
        let configService = ConfigurationService.sessionTestService(configDirectory: tempDir.path, ruleCollectionStore: collectionStore, customRulesStore: customStore)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collectionStore,
            customRulesStore: customStore,
            configurationService: configService,
            eventListener: KanataEventListener()
        )

        let collectionID = RuleCollectionIdentifier.homeRowMods

        // Install
        let installed = await manager.toggleCollection(
            id: collectionID,
            isEnabled: true,
            autoResolveConflicts: true,
            bypassOwnershipCheck: true
        )
        XCTAssertTrue(installed)

        // Uninstall
        let uninstalled = await manager.toggleCollection(
            id: collectionID,
            isEnabled: false,
            autoResolveConflicts: true,
            bypassOwnershipCheck: true
        )
        XCTAssertTrue(uninstalled)

        // Verify tap-hold idle labels are empty after uninstall
        let collections = await collectionStore.loadCollections()
        let vm = KeyboardVisualizationViewModel()
        vm.updateTapHoldIdleLabels(from: collections)
        XCTAssertTrue(
            vm.tapHoldIdleLabels.isEmpty,
            "Should have no tap-hold idle labels after pack uninstall"
        )
    }
}
