@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class GenericPackConfigTests: XCTestCase {
    private var originalInstalledPacks: [InstalledPackRecord] = []

    override func setUp() async throws {
        try await super.setUp()
        originalInstalledPacks = await InstalledPackTracker.shared.allInstalled()
    }

    override func tearDown() async throws {
        let current = await InstalledPackTracker.shared.allInstalled()
        for record in current {
            if !originalInstalledPacks.contains(where: { $0.packID == record.packID }) {
                try await InstalledPackTracker.shared.remove(packID: record.packID)
            }
        }
        for record in originalInstalledPacks {
            if await !(InstalledPackTracker.shared.isInstalled(packID: record.packID)) {
                try await InstalledPackTracker.shared.upsert(record)
            }
        }
        try await super.tearDown()
    }

    // MARK: - PackCollectionSnapshot Round-Trip

    func testPackCollectionSnapshotRoundTrip() throws {
        let config = RuleCollectionConfiguration.tapHoldPicker(TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [],
            holdOptions: [],
            selectedTapOutput: "esc",
            selectedHoldOutput: "hyper"
        ))
        let configJSON = try JSONEncoder().encode(config)

        let snapshot = PackCollectionSnapshot(
            packID: "test.pack",
            entries: [
                PackCollectionSnapshot.Entry(
                    collectionID: RuleCollectionIdentifier.capsLockRemap,
                    wasEnabled: true,
                    configurationJSON: configJSON
                ),
            ]
        )

        try PackCollectionSnapshot.save(snapshot)
        defer { PackCollectionSnapshot.remove(for: "test.pack") }

        let loaded = PackCollectionSnapshot.load(for: "test.pack")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.packID, "test.pack")
        XCTAssertEqual(loaded?.entries.count, 1)
        XCTAssertEqual(loaded?.entries.first?.collectionID, RuleCollectionIdentifier.capsLockRemap)
        XCTAssertEqual(loaded?.entries.first?.wasEnabled, true)

        let decodedConfig = try JSONDecoder().decode(
            RuleCollectionConfiguration.self,
            from: XCTUnwrap(loaded?.entries.first?.configurationJSON)
        )
        XCTAssertEqual(decodedConfig, config)
    }

    // MARK: - Quick Launcher

    func testQuickLauncherIsSystemPack() {
        XCTAssertTrue(PackRegistry.launcher.isSystemPack)
        XCTAssertEqual(PackRegistry.launcher.managedDefaults.count, 1)
    }

    func testQuickLauncherManagedCollectionIDs() {
        let ids = PackRegistry.launcher.managedCollectionIDs
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.launcher))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.capsLockRemap))
    }

    func testQuickLauncherManagedDefaultIsCapsLockRemap() {
        let managed = PackRegistry.launcher.managedDefaults.first
        XCTAssertNotNil(managed)
        XCTAssertEqual(managed?.collectionID, RuleCollectionIdentifier.capsLockRemap)
        XCTAssertEqual(managed?.displayName, "Caps Lock Remap")

        if case let .tapHoldPicker(config) = managed?.defaultConfiguration {
            XCTAssertEqual(config.selectedTapOutput, "esc")
            XCTAssertEqual(config.selectedHoldOutput, "hyper")
        } else {
            XCTFail("Expected tapHoldPicker configuration")
        }
    }

    @MainActor
    func testQuickLauncherInstallConfiguresCapsLockRemap() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        let record = try await PackInstaller.shared.install(
            PackRegistry.launcher,
            manager: manager
        )
        XCTAssertEqual(record.packID, PackRegistry.launcher.id)

        // Caps Lock Remap should be enabled with tap=esc, hold=hyper
        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertTrue(capsCollection?.isEnabled ?? false, "Caps Lock Remap should be enabled")
        if let config = capsCollection?.configuration.tapHoldPickerConfig {
            XCTAssertEqual(config.selectedTapOutput, "esc")
            XCTAssertEqual(config.selectedHoldOutput, "hyper")
        } else {
            XCTFail("Caps Lock Remap should have tapHoldPicker config after launcher install")
        }

        // Launcher collection itself should be enabled
        let launcherCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.launcher }
        XCTAssertTrue(launcherCollection?.isEnabled ?? false, "Launcher collection should be enabled")
    }

    @MainActor
    func testQuickLauncherUninstallRestoresCapsLockRemap() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        // Capture pre-install caps lock state
        let preCapsEnabled = manager.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.capsLockRemap }?.isEnabled ?? false
        let preCapsConfig = manager.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.capsLockRemap }?.configuration

        // Install then uninstall
        _ = try await PackInstaller.shared.install(PackRegistry.launcher, manager: manager)
        try await PackInstaller.shared.uninstall(packID: PackRegistry.launcher.id, manager: manager)

        // Caps Lock Remap should revert to pre-install state
        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertEqual(
            capsCollection?.isEnabled ?? !preCapsEnabled,
            preCapsEnabled,
            "Caps Lock Remap enabled state should revert"
        )

        if let preCapsConfig {
            XCTAssertEqual(
                capsCollection?.configuration,
                preCapsConfig,
                "Caps Lock Remap config should revert"
            )
        }

        // Launcher collection should be disabled
        let launcherCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.launcher }
        XCTAssertFalse(launcherCollection?.isEnabled ?? true, "Launcher should be disabled after uninstall")

        // Snapshot file should be cleaned up
        XCTAssertNil(
            PackCollectionSnapshot.load(for: PackRegistry.launcher.id),
            "Snapshot should be removed after uninstall"
        )
    }

    @MainActor
    func testQuickLauncherInstallCreatesSnapshotFile() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        _ = try await PackInstaller.shared.install(PackRegistry.launcher, manager: manager)

        let snapshot = PackCollectionSnapshot.load(for: PackRegistry.launcher.id)
        XCTAssertNotNil(snapshot, "Snapshot should exist after install")
        XCTAssertEqual(snapshot?.entries.count, 1, "Should snapshot one managed collection")
        XCTAssertEqual(snapshot?.entries.first?.collectionID, RuleCollectionIdentifier.capsLockRemap)
    }

    // MARK: - Legacy Vallack Migration

    func testLegacyVallackSnapshotMigration() throws {
        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/keypath/vallack-system-snapshot.json")

        let legacySnapshot: [String: Any] = [
            "homeRowModsEnabled": true,
            "homeRowLayerTogglesEnabled": false,
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacySnapshot)
        try legacyData.write(to: legacyURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        let migrated = PackCollectionSnapshot.loadLegacyVallack()
        XCTAssertNotNil(migrated)
        XCTAssertEqual(migrated?.packID, "com.keypath.pack.vallack-system")
        XCTAssertEqual(migrated?.entries.count, 2)

        let modsEntry = migrated?.entries.first { $0.collectionID == RuleCollectionIdentifier.homeRowMods }
        XCTAssertNotNil(modsEntry)
        XCTAssertTrue(modsEntry?.wasEnabled ?? false)

        let togglesEntry = migrated?.entries.first { $0.collectionID == RuleCollectionIdentifier.homeRowLayerToggles }
        XCTAssertNotNil(togglesEntry)
        XCTAssertFalse(togglesEntry?.wasEnabled ?? true)
    }

    // MARK: - Helpers

    @MainActor
    private func makeTestManager() throws -> (RuleCollectionsManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("generic-pack-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manager = RuleCollectionsManager(
            ruleCollectionStore: RuleCollectionStore(
                fileURL: tempDir.appendingPathComponent("RuleCollections.json")
            ),
            customRulesStore: CustomRulesStore(
                fileURL: tempDir.appendingPathComponent("CustomRules.json")
            ),
            configurationService: ConfigurationService(configDirectory: tempDir.path),
            eventListener: KanataEventListener()
        )
        return (manager, tempDir)
    }
}
