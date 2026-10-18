import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class LauncherStoreTransactionTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!
    private var store: LauncherStore!
    private let first = LauncherMapping(key: "q", action: .launchApp(name: "Safari", bundleId: "com.apple.Safari"))
    private let second = LauncherMapping(key: "d", action: .launchApp(name: "Finder", bundleId: "com.apple.finder"))

    override func setUp() async throws {
        try await super.setUp()
        try SessionBridgeTestFixture.requireAvailable()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService.sessionTestService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        var launcher = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first { $0.id == RuleCollectionIdentifier.launcher })
        var config = try XCTUnwrap(launcher.configuration.launcherGridConfig)
        config.mappings = [first, second]
        launcher.configuration = .launcherGrid(config)
        launcher.isEnabled = true
        manager.ruleCollections = [launcher]
        manager.customRules = []
        try await service.saveRuleState(ruleCollections: [launcher], customRules: [], collectionStore: collections, customStore: rules)
        manager.onRulesChanged = { ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .applied) }
        store = LauncherStore(testMappings: [first, second], manager: manager)
    }

    override func tearDown() async throws {
        store = nil
        manager = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try await super.tearDown()
    }

    func testBackupRestoreRestoresEditorAndConfigAndAllowsNextEdit() async throws {
        let backups = ConfigBackupManager(configPath: directory.appendingPathComponent("keypath.kbd").path)
        XCTAssertTrue(backups.createPreEditBackup())
        let backup = try XCTUnwrap(backups.getAvailableBackups().first)
        store.deleteMapping(first.id)
        await store.pendingSave?.value
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .applied)
        }
        let result = await manager.restoreConfigurationBackup(backup)
        XCTAssertTrue(result.success, "\(String(describing: result.error))")
        XCTAssertEqual(reloads, 1)
        XCTAssertTrue(try String(contentsOf: directory.appendingPathComponent("keypath.kbd"), encoding: .utf8).contains("act_launcher_q"))
        let persisted = try await manager.ruleCollectionStore.loadForMutation()
        let restored = try XCTUnwrap(persisted.first?.configuration.launcherGridConfig)
        XCTAssertEqual(Set(restored.mappings.map(\.id)), [first.id, second.id])
        XCTAssertEqual(manager.ruleCollections.first?.configuration.launcherGridConfig?.mappings.count, 2)
        var edited = restored
        edited.mappings.removeAll { $0.id == first.id }
        let saved = await manager.applyLauncherConfig(id: RuleCollectionIdentifier.launcher, config: edited)
        XCTAssertTrue(saved, "Restore must not poison subsequent saves")
    }

    func testBackupRestoresGenerationPreferencesAndReportsPendingRuntime() async throws {
        let defaults = manager.preferencesService.persistenceDefaults
        let preferences = RuleBackupPreferences(defaults: defaults)
        let backups = ConfigBackupManager(configPath: directory.appendingPathComponent("keypath.kbd").path)
        XCTAssertTrue(backups.createPreEditBackup(generationPreferences: preferences))
        let backup = try XCTUnwrap(backups.getAvailableBackups().first)
        let changed = await manager.applyShortcutListGenerationInput(
            ShortcutListGenerationInput(triggerMode: .tapToToggle, holdDelayPreset: .short, customHoldDelayMs: 310)
        )
        XCTAssertTrue(changed)
        manager.onRulesChanged = {
            ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .pending)
        }
        let result = await manager.restoreConfigurationBackup(backup)
        XCTAssertTrue(result.success, "\(String(describing: result.error))")
        XCTAssertEqual(result.reloadResult?.disposition, .pending)
        XCTAssertEqual(defaults.string(forKey: RecoverableRuleWrite.PreferenceRole.contextHUDTriggerMode.key), preferences.trigger)
        XCTAssertEqual(defaults.string(forKey: RecoverableRuleWrite.PreferenceRole.contextHUDHoldDelayPreset.key), preferences.delayPreset)
        XCTAssertEqual(manager.preferencesService.contextHUDTriggerMode.rawValue, preferences.trigger)
    }

    func testRejectedBackupRestoreRollsBackFilesAndVisibleRules() async throws {
        let backups = ConfigBackupManager(configPath: directory.appendingPathComponent("keypath.kbd").path)
        XCTAssertTrue(backups.createPreEditBackup())
        let backup = try XCTUnwrap(backups.getAvailableBackups().first)
        store.deleteMapping(first.id)
        await store.pendingSave?.value
        let paths = ["keypath.kbd", "RuleCollections.json", "CustomRules.json"]
        let before = try paths.map { try Data(contentsOf: directory.appendingPathComponent($0)) }
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            return ReloadResult(success: reloads > 1, response: nil, errorMessage: "Rejected test candidate", protocol: nil,
                                disposition: reloads > 1 ? .applied : .rejected)
        }
        let result = await manager.restoreConfigurationBackup(backup)
        XCTAssertFalse(result.success)
        XCTAssertEqual(reloads, 2, "The prior runtime configuration also needs to be reapplied")
        XCTAssertEqual(try paths.map { try Data(contentsOf: directory.appendingPathComponent($0)) }, before)
        XCTAssertEqual(manager.ruleCollections.first?.configuration.launcherGridConfig?.mappings.map(\.id), [second.id])
    }

    func testBackupWithMismatchedMetadataIsRejectedWithoutWrites() async throws {
        let backups = ConfigBackupManager(configPath: directory.appendingPathComponent("keypath.kbd").path)
        XCTAssertTrue(backups.createPreEditBackup())
        let backup = try XCTUnwrap(backups.getAvailableBackups().first)
        let sidecar = URL(fileURLWithPath: backup.fullPath + ".json")
        let snapshot = try RuleBackupSnapshot.read(backup)
        let corrupted = RuleBackupSnapshot(version: 1, config: snapshot.config, collections: Data("[]".utf8), customRules: Data("[]".utf8))
        try JSONEncoder().encode(corrupted).write(to: sidecar)
        let paths = ["keypath.kbd", "RuleCollections.json", "CustomRules.json"]
        let before = try paths.map { try Data(contentsOf: directory.appendingPathComponent($0)) }
        let result = await manager.restoreConfigurationBackup(backup)
        XCTAssertFalse(result.success)
        XCTAssertEqual(try paths.map { try Data(contentsOf: directory.appendingPathComponent($0)) }, before)
    }

    func testDeleteCommitsGeneratedConfigAndAllowsNextTourSave() async throws {
        store.deleteMapping(first.id)
        await store.pendingSave?.value
        let content = try String(contentsOf: directory.appendingPathComponent("keypath.kbd"), encoding: .utf8)
        XCTAssertFalse(content.contains("act_launcher_q"), "Deleting a shortcut must update the generated config too")
        let persisted = try await manager.ruleCollectionStore.loadForMutation()
        var config = try XCTUnwrap(persisted.first { $0.id == RuleCollectionIdentifier.launcher }?.configuration.launcherGridConfig)
        config.mappings.append(LauncherMapping(key: "s", action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")))
        let saved = await manager.applyLauncherConfig(id: RuleCollectionIdentifier.launcher, config: config)
        XCTAssertTrue(saved, "A drawer edit must not poison the next tour save's reproducibility check")
    }

    func testDeletedShortcutDisappearsFromVisibleKeyboardWithoutLayerSwitch() async {
        let keyboard = KeyboardVisualizationViewModel()
        keyboard.currentLayerName = "base" // Launcher drawer previews icons while runtime remains on base.
        keyboard.launcherMappings = ["q": first, "d": second]
        keyboard.cachedLauncherMappings = keyboard.launcherMappings
        store.deleteMapping(first.id)
        await store.pendingSave?.value
        await keyboard.prewarmLauncherMappings(store: manager.ruleCollectionStore).value
        XCTAssertNil(keyboard.launcherMappings["q"], "A refreshed cache must also refresh the currently visible keyboard")
        XCTAssertEqual(keyboard.launcherMappings["d"]?.id, second.id)
        XCTAssertNil(keyboard.cachedLauncherMappings?["q"])
    }

    func testQueuedEditsMergeWithoutLosingOtherMappings() async throws {
        let extra = LauncherMapping(key: "s", action: .openURL("https://example.com"))
        store.deleteMapping(first.id)
        store.addMapping(extra)
        await store.pendingSave?.value
        let persisted = try await manager.ruleCollectionStore.loadForMutation()
        let mappings = try XCTUnwrap(persisted.first { $0.id == RuleCollectionIdentifier.launcher }?.configuration.launcherGridConfig).mappings
        XCTAssertEqual(Set(mappings.map(\.id)), [second.id, extra.id])
        let content = try String(contentsOf: directory.appendingPathComponent("keypath.kbd"), encoding: .utf8)
        XCTAssertFalse(content.contains("act_launcher_q"))
        XCTAssertTrue(content.contains("act_launcher_s"))
        XCTAssertNil(store.saveError)
        XCTAssertFalse(store.isSaving)
    }

    func testUnreproducibleConfigRejectsDeleteWithoutPublishingJSONOrUI() async throws {
        let configURL = directory.appendingPathComponent("keypath.kbd")
        let custom = try String(contentsOf: configURL, encoding: .utf8).replacingOccurrences(of: "act_launcher_q", with: "handwritten_q")
        try custom.write(to: configURL, atomically: true, encoding: .utf8)
        let jsonURL = directory.appendingPathComponent("RuleCollections.json")
        let originalJSON = try Data(contentsOf: jsonURL)
        store.deleteMapping(first.id)
        await store.pendingSave?.value
        XCTAssertEqual(try Data(contentsOf: jsonURL), originalJSON)
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), custom)
        XCTAssertTrue(store.mappings.contains { $0.id == first.id })
        XCTAssertNotNil(store.saveError)
        XCTAssertFalse(store.isSaving)
    }
}
