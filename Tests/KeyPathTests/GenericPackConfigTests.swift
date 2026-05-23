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

    // MARK: - Install Over Existing Customization

    @MainActor
    func testInstallOverExistingCustomCapsLockRemap() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        // Pre-customize: set caps lock to tap=Control, hold=Meh
        let catalog = RuleCollectionCatalog().defaultCollections()
        if let capsFromCatalog = catalog.first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            var customCaps = capsFromCatalog
            customCaps.configuration = .tapHoldPicker(TapHoldPickerConfig(
                inputKey: "caps",
                tapOptions: capsFromCatalog.configuration.tapHoldPickerConfig?.tapOptions ?? [],
                holdOptions: capsFromCatalog.configuration.tapHoldPickerConfig?.holdOptions ?? [],
                selectedTapOutput: "lctl",
                selectedHoldOutput: "meh"
            ))
            customCaps.isEnabled = true
            manager.ruleCollections.append(customCaps)
        }

        // Install launcher — should apply its defaults (auto-approved in test env)
        _ = try await PackInstaller.shared.install(PackRegistry.launcher, manager: manager)

        // Verify pack defaults were applied
        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertEqual(capsCollection?.configuration.tapHoldPickerConfig?.selectedTapOutput, "esc")
        XCTAssertEqual(capsCollection?.configuration.tapHoldPickerConfig?.selectedHoldOutput, "hyper")

        // Verify snapshot captured the PRE-INSTALL custom config
        let snapshot = PackCollectionSnapshot.load(for: PackRegistry.launcher.id)
        XCTAssertNotNil(snapshot)
        let capsEntry = snapshot?.entries.first { $0.collectionID == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertNotNil(capsEntry)
        XCTAssertTrue(capsEntry?.wasEnabled ?? false, "Snapshot should record caps was enabled before install")
        if let configJSON = capsEntry?.configurationJSON,
           let restoredConfig = try? JSONDecoder().decode(RuleCollectionConfiguration.self, from: configJSON)
        {
            XCTAssertEqual(
                restoredConfig.tapHoldPickerConfig?.selectedTapOutput, "lctl",
                "Snapshot should capture the pre-install custom tap output"
            )
            XCTAssertEqual(
                restoredConfig.tapHoldPickerConfig?.selectedHoldOutput, "meh",
                "Snapshot should capture the pre-install custom hold output"
            )
        } else {
            XCTFail("Should be able to decode snapshot config")
        }
    }

    @MainActor
    func testInstallOverCustomConfigThenUninstallRestoresCustomConfig() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        // Pre-customize caps lock
        let catalog = RuleCollectionCatalog().defaultCollections()
        if let capsFromCatalog = catalog.first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            var customCaps = capsFromCatalog
            customCaps.configuration = .tapHoldPicker(TapHoldPickerConfig(
                inputKey: "caps",
                tapOptions: capsFromCatalog.configuration.tapHoldPickerConfig?.tapOptions ?? [],
                holdOptions: capsFromCatalog.configuration.tapHoldPickerConfig?.holdOptions ?? [],
                selectedTapOutput: "bspc",
                selectedHoldOutput: "lctl"
            ))
            customCaps.isEnabled = true
            manager.ruleCollections.append(customCaps)
        }

        // Install, then uninstall
        _ = try await PackInstaller.shared.install(PackRegistry.launcher, manager: manager)
        try await PackInstaller.shared.uninstall(packID: PackRegistry.launcher.id, manager: manager)

        // Should restore the pre-install custom config, not the pack defaults
        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertEqual(capsCollection?.configuration.tapHoldPickerConfig?.selectedTapOutput, "bspc")
        XCTAssertEqual(capsCollection?.configuration.tapHoldPickerConfig?.selectedHoldOutput, "lctl")
        XCTAssertTrue(capsCollection?.isEnabled ?? false, "Caps lock should remain enabled (was enabled before install)")
    }

    // MARK: - Keep My Settings (Decline Override on Install)

    @MainActor
    func testKeepMySettingsSkipsConfigOverride() async throws {
        TestEnvironment.forceTestMode = true
        PackInstaller.testOverrideApplyDefault = false
        defer {
            TestEnvironment.forceTestMode = false
            PackInstaller.testOverrideApplyDefault = nil
        }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        // Pre-customize caps lock with non-default config
        let catalog = RuleCollectionCatalog().defaultCollections()
        if let capsFromCatalog = catalog.first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            var customCaps = capsFromCatalog
            customCaps.configuration = .tapHoldPicker(TapHoldPickerConfig(
                inputKey: "caps",
                tapOptions: capsFromCatalog.configuration.tapHoldPickerConfig?.tapOptions ?? [],
                holdOptions: capsFromCatalog.configuration.tapHoldPickerConfig?.holdOptions ?? [],
                selectedTapOutput: "lctl",
                selectedHoldOutput: "meh"
            ))
            customCaps.isEnabled = true
            manager.ruleCollections.append(customCaps)
        }

        // Install with "Keep My Settings"
        _ = try await PackInstaller.shared.install(PackRegistry.launcher, manager: manager)

        // Config should NOT have been overridden — user chose to keep theirs
        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertTrue(capsCollection?.isEnabled ?? false, "Collection should still be enabled")
        XCTAssertEqual(
            capsCollection?.configuration.tapHoldPickerConfig?.selectedTapOutput, "lctl",
            "Tap output should remain user's choice, not pack default"
        )
        XCTAssertEqual(
            capsCollection?.configuration.tapHoldPickerConfig?.selectedHoldOutput, "meh",
            "Hold output should remain user's choice, not pack default"
        )
    }

    // MARK: - Silent Apply When Collection Has Catalog Defaults

    @MainActor
    func testInstallAppliesSilentlyWhenCollectionHasCatalogDefaults() async throws {
        TestEnvironment.forceTestMode = true
        PackInstaller.testOverrideApplyDefault = false
        defer {
            TestEnvironment.forceTestMode = false
            PackInstaller.testOverrideApplyDefault = nil
        }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        // Add caps lock from catalog with its default config (tap=hyper, hold=hyper)
        // and mark it enabled — simulating a user who enabled it but never changed settings
        let catalog = RuleCollectionCatalog().defaultCollections()
        if let capsFromCatalog = catalog.first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            var caps = capsFromCatalog
            caps.isEnabled = true
            manager.ruleCollections.append(caps)
        }

        // Install with testOverrideApplyDefault=false (would decline the dialog)
        // but the dialog should NOT appear because config matches catalog defaults.
        // The pack's config should be applied silently.
        _ = try await PackInstaller.shared.install(PackRegistry.launcher, manager: manager)

        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertEqual(
            capsCollection?.configuration.tapHoldPickerConfig?.selectedTapOutput, "esc",
            "Pack default should be applied silently when collection has catalog defaults"
        )
        XCTAssertEqual(
            capsCollection?.configuration.tapHoldPickerConfig?.selectedHoldOutput, "hyper",
            "Pack default should be applied silently when collection has catalog defaults"
        )
    }

    // MARK: - Nil Default Configuration (Enable-Only)

    @MainActor
    func testNilDefaultConfigOnlyEnablesWithoutChangingConfig() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.vallackSystem.id)
        }

        // Vallack Navigation has defaultConfiguration: nil in managedDefaults.
        // Pre-add the nav collection from catalog (disabled).
        let catalog = RuleCollectionCatalog().defaultCollections()
        if let navFromCatalog = catalog.first(where: { $0.id == RuleCollectionIdentifier.vallackNavigation }) {
            var nav = navFromCatalog
            nav.isEnabled = false
            manager.ruleCollections.append(nav)
        }

        let configBefore = manager.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.vallackNavigation }?.configuration

        _ = try await PackInstaller.shared.install(PackRegistry.vallackSystem, manager: manager)

        let navCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertTrue(navCollection?.isEnabled ?? false, "Should be enabled after install")
        XCTAssertEqual(
            navCollection?.configuration, configBefore,
            "Config should be unchanged — nil defaultConfiguration means enable-only"
        )
    }

    // MARK: - Uninstall After User Modification

    @MainActor
    func testUninstallAfterUserModificationDetectsChange() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        // Install launcher (applies tap=esc, hold=hyper)
        _ = try await PackInstaller.shared.install(PackRegistry.launcher, manager: manager)

        // Simulate user modifying the config AFTER install
        if let i = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            manager.ruleCollections[i].configuration = .tapHoldPicker(TapHoldPickerConfig(
                inputKey: "caps",
                tapOptions: [],
                holdOptions: [],
                selectedTapOutput: "bspc",
                selectedHoldOutput: "lctl"
            ))
        }

        // Uninstall — test env auto-approves restore even when modified
        try await PackInstaller.shared.uninstall(packID: PackRegistry.launcher.id, manager: manager)

        // Should have restored the pre-install config (whatever was there before),
        // not kept the user's post-install modification
        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertNotEqual(
            capsCollection?.configuration.tapHoldPickerConfig?.selectedTapOutput, "bspc",
            "Post-install modification should not persist after restore"
        )
    }

    @MainActor
    func testUninstallKeepCurrentWhenUserModified() async throws {
        TestEnvironment.forceTestMode = true
        PackInstaller.testOverrideRestore = false
        defer {
            TestEnvironment.forceTestMode = false
            PackInstaller.testOverrideRestore = nil
        }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        // Install launcher (applies tap=esc, hold=hyper)
        _ = try await PackInstaller.shared.install(PackRegistry.launcher, manager: manager)

        // Simulate user modifying after install
        if let i = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            manager.ruleCollections[i].configuration = .tapHoldPicker(TapHoldPickerConfig(
                inputKey: "caps",
                tapOptions: [],
                holdOptions: [],
                selectedTapOutput: "bspc",
                selectedHoldOutput: "lctl"
            ))
        }

        // Uninstall with "Keep Current"
        try await PackInstaller.shared.uninstall(packID: PackRegistry.launcher.id, manager: manager)

        // User's modification should be preserved
        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertEqual(
            capsCollection?.configuration.tapHoldPickerConfig?.selectedTapOutput, "bspc",
            "User's modification should be kept when they choose 'Keep Current'"
        )
        XCTAssertEqual(
            capsCollection?.configuration.tapHoldPickerConfig?.selectedHoldOutput, "lctl",
            "User's modification should be kept when they choose 'Keep Current'"
        )
    }

    // MARK: - Two System Packs Simultaneously

    @MainActor
    func testTwoSystemPacksInstalledSimultaneously() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.vallackSystem.id)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }

        // Install both system packs
        _ = try await PackInstaller.shared.install(PackRegistry.vallackSystem, manager: manager)
        _ = try await PackInstaller.shared.install(PackRegistry.launcher, manager: manager)

        // Vallack collections should be enabled
        let navCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertTrue(navCollection?.isEnabled ?? false, "Vallack nav should be enabled")
        let modsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.homeRowMods }
        XCTAssertTrue(modsCollection?.isEnabled ?? false, "Home Row Mods should be enabled")

        // Launcher collections should be enabled
        let launcherCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.launcher }
        XCTAssertTrue(launcherCollection?.isEnabled ?? false, "Launcher should be enabled")
        let capsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertTrue(capsCollection?.isEnabled ?? false, "Caps Lock Remap should be enabled")
        XCTAssertEqual(capsCollection?.configuration.tapHoldPickerConfig?.selectedTapOutput, "esc")
        XCTAssertEqual(capsCollection?.configuration.tapHoldPickerConfig?.selectedHoldOutput, "hyper")

        // Uninstall Launcher — should not affect Vallack collections
        try await PackInstaller.shared.uninstall(packID: PackRegistry.launcher.id, manager: manager)

        let navAfter = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertTrue(navAfter?.isEnabled ?? false, "Vallack nav should still be enabled after launcher uninstall")
        let modsAfter = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.homeRowMods }
        XCTAssertTrue(modsAfter?.isEnabled ?? false, "Home Row Mods should still be enabled after launcher uninstall")
    }

    // MARK: - Uninstall Without Snapshot

    @MainActor
    func testLauncherUninstallWithoutSnapshotDoesNotCrash() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Register as installed without going through install flow (no snapshot created)
        try await InstalledPackTracker.shared.upsert(InstalledPackRecord(
            packID: PackRegistry.launcher.id,
            version: PackRegistry.launcher.version
        ))

        // Ensure launcher collection exists and is enabled
        let catalog = RuleCollectionCatalog().defaultCollections()
        if let launcherFromCatalog = catalog.first(where: { $0.id == RuleCollectionIdentifier.launcher }) {
            var launcher = launcherFromCatalog
            launcher.isEnabled = true
            manager.ruleCollections.append(launcher)
        }

        // Should not crash
        try await PackInstaller.shared.uninstall(
            packID: PackRegistry.launcher.id,
            manager: manager
        )

        let launcherCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.launcher }
        XCTAssertFalse(launcherCollection?.isEnabled ?? true, "Launcher should be disabled after uninstall")
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
