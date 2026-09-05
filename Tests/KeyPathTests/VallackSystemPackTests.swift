@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

final class VallackSystemPackTests: XCTestCase {
    func testSnapshotWritesStayInsideTestSandbox() throws {
        let id = "sandbox-\(UUID().uuidString)"
        let url = PackCollectionSnapshot.snapshotURL(for: id)
        XCTAssertTrue(url.path.hasPrefix(AppPaths.testSandboxDirectory.path + "/"))
        defer { PackCollectionSnapshot.remove(for: id) }
        try PackCollectionSnapshot.save(PackCollectionSnapshot(packID: id, entries: []))
        XCTAssertNotNil(PackCollectionSnapshot.load(for: id))
    }

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

    // MARK: - Nav Layer Collection

    func testVallackNavigationCollectionExistsInCatalog() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertNotNil(collection, "Vallack Navigation collection must exist in catalog")
    }

    func testVallackNavigationHas18Mappings() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = try XCTUnwrap(catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation })
        XCTAssertEqual(collection.mappings.count, 18, "Should have 18 key mappings (10 right hand + 8 left hand)")
    }

    func testVallackNavigationTargetsCustomLayer() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = try XCTUnwrap(catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation })
        XCTAssertEqual(collection.targetLayer, .custom("vallack-nav"))
    }

    func testVallackNavigationHasNoMomentaryActivator() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = try XCTUnwrap(catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation })
        XCTAssertNil(
            collection.momentaryActivator,
            "Activation is handled by homeRowLayerToggles (F/J), not a momentaryActivator"
        )
    }

    func testVallackNavigationIsDisabledByDefault() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = try XCTUnwrap(catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation })
        XCTAssertFalse(collection.isEnabled)
        XCTAssertFalse(collection.isSystemDefault)
    }

    func testVallackNavigationContainsExpectedArrowMappings() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = try XCTUnwrap(catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation })
        let mappingsByInput = Dictionary(uniqueKeysWithValues: collection.mappings.map { ($0.input, $0) })

        XCTAssertEqual(mappingsByInput["h"]?.action, .keystroke(key: "left"))
        XCTAssertEqual(mappingsByInput["j"]?.action, .keystroke(key: "down"))
        XCTAssertEqual(mappingsByInput["k"]?.action, .keystroke(key: "up"))
        XCTAssertEqual(mappingsByInput["l"]?.action, .keystroke(key: "right"))
    }

    func testVallackNavigationContainsClipboardAndEditing() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = try XCTUnwrap(catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation })
        let mappingsByInput = Dictionary(uniqueKeysWithValues: collection.mappings.map { ($0.input, $0) })

        XCTAssertEqual(mappingsByInput["y"]?.action, .keystroke(key: "M-c"), "y should be Copy")
        XCTAssertEqual(mappingsByInput[";"]?.action, .keystroke(key: "M-v"), "; should be Paste")
        XCTAssertEqual(mappingsByInput["u"]?.action, .keystroke(key: "bspc"), "u should be Backspace")
        XCTAssertEqual(mappingsByInput["i"]?.action, .keystroke(key: "ret"), "i should be Enter")
    }

    func testVallackNavigationInputKeysAreUnique() throws {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = try XCTUnwrap(catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation })
        let inputs = collection.mappings.map(\.input)
        XCTAssertEqual(Set(inputs).count, inputs.count, "No duplicate input keys")
    }

    // MARK: - Config Presets

    func testVallackTwoRowSplitHas6Keys() {
        let preset = HomeRowModsConfig.vallackTwoRowSplit
        XCTAssertEqual(preset.count, 6, "Two-row split maps Q/W/E on left, U/I/O on right")
    }

    func testVallackTwoRowSplitUsesTopRowKeys() {
        let preset = HomeRowModsConfig.vallackTwoRowSplit
        let expectedKeys: Set = ["q", "w", "e", "u", "i", "o"]
        XCTAssertEqual(Set(preset.keys), expectedKeys)
    }

    func testVallackTwoRowSplitMapsToValidModifiers() {
        let validModifiers: Set = ["lctl", "lalt", "lmet", "lsft", "rctl", "ralt", "rmet", "rsft"]
        for (key, modifier) in HomeRowModsConfig.vallackTwoRowSplit {
            XCTAssertTrue(
                validModifiers.contains(modifier),
                "Key '\(key)' maps to '\(modifier)' which is not a valid kanata modifier"
            )
        }
    }

    func testVallackTwoRowSplitIsMirrored() {
        let preset = HomeRowModsConfig.vallackTwoRowSplit
        XCTAssertEqual(preset["q"], "lctl")
        XCTAssertEqual(preset["o"], "rctl")
        XCTAssertEqual(preset["w"], "lalt")
        XCTAssertEqual(preset["i"], "ralt")
        XCTAssertEqual(preset["e"], "lmet")
        XCTAssertEqual(preset["u"], "rmet")
    }

    func testVallackTopRowKeysMatchPresetKeys() {
        let presetKeys = Set(HomeRowModsConfig.vallackTwoRowSplit.keys)
        let topRowKeys = Set(HomeRowModsConfig.vallackTopRowKeys)
        XCTAssertEqual(presetKeys, topRowKeys)
    }

    func testVallackLayerAssignmentsTargetNavLayer() {
        let assignments = HomeRowLayerTogglesConfig.vallackLayerAssignments
        XCTAssertEqual(assignments.count, 2)
        XCTAssertEqual(assignments["f"], "vallack-nav")
        XCTAssertEqual(assignments["j"], "vallack-nav")
    }

    // MARK: - Pack Registration

    func testVallackSystemPackExistsInStarterKit() {
        let ids = Set(PackRegistry.starterKit.map(\.id))
        XCTAssertTrue(ids.contains("com.keypath.pack.vallack-system"))
    }

    func testVallackSystemPackPointsAtNavCollection() {
        let pack = PackRegistry.pack(id: "com.keypath.pack.vallack-system")
        XCTAssertNotNil(pack)
        XCTAssertEqual(pack?.associatedCollectionID, RuleCollectionIdentifier.vallackNavigation)
    }

    func testVallackSystemPackHasNoDirectBindings() {
        let pack = PackRegistry.vallackSystem
        XCTAssertTrue(pack.bindings.isEmpty, "System packs configure via presets, not direct bindings")
    }

    func testVallackSystemPackIsNotVisualOnly() {
        XCTAssertFalse(PackRegistry.vallackSystem.visualOnly)
    }

    func testVallackSystemPackIsSystemPack() {
        XCTAssertTrue(PackRegistry.vallackSystem.isSystemPack)
        XCTAssertEqual(PackRegistry.vallackSystem.managedDefaults.count, 4)
    }

    func testManagedCollectionIDsDerivedFromDefaults() {
        let ids = PackRegistry.vallackSystem.managedCollectionIDs
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.vallackNavigation))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowMods))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowLayerToggles))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowArrows))
    }

    func testNonSystemPackIsNotSystemPack() {
        let pack = PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape")
        XCTAssertNotNil(pack)
        XCTAssertFalse(pack?.isSystemPack ?? true)
    }

    // MARK: - PackInstaller Snapshot/Restore

    @MainActor
    func testVallackInstallAppliesConfigPresets() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let record = try await PackInstaller.shared.install(
            PackRegistry.vallackSystem,
            manager: manager
        )
        XCTAssertEqual(record.packID, PackRegistry.vallackSystem.id)

        let collections = manager.ruleCollections

        // Nav layer should be enabled
        let navCollection = collections.first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertTrue(navCollection?.isEnabled ?? false, "Vallack nav collection should be enabled")

        // Home Row Mods should be enabled with Vallack top-row config
        let modsCollection = collections.first { $0.id == RuleCollectionIdentifier.homeRowMods }
        XCTAssertTrue(modsCollection?.isEnabled ?? false, "Home Row Mods should be enabled")
        if let config = modsCollection?.configuration.homeRowModsConfig {
            XCTAssertEqual(config.enabledKeys, Set(HomeRowModsConfig.vallackTopRowKeys))
            XCTAssertEqual(config.modifierAssignments, HomeRowModsConfig.vallackTwoRowSplit)
        } else {
            XCTFail("Home Row Mods should have homeRowModsConfig after Vallack install")
        }

        // Home Row Layer Toggles should be enabled with Vallack assignments
        let togglesCollection = collections.first { $0.id == RuleCollectionIdentifier.homeRowLayerToggles }
        XCTAssertTrue(togglesCollection?.isEnabled ?? false, "Layer Toggles should be enabled")
        if let config = togglesCollection?.configuration.homeRowLayerTogglesConfig {
            XCTAssertEqual(config.enabledKeys, Set(["f", "j"]))
            XCTAssertEqual(config.layerAssignments, HomeRowLayerTogglesConfig.vallackLayerAssignments)
        } else {
            XCTFail("Layer Toggles should have homeRowLayerTogglesConfig after Vallack install")
        }

        let arrowsCollection = collections.first { $0.id == RuleCollectionIdentifier.homeRowArrows }
        XCTAssertFalse(arrowsCollection?.isEnabled ?? true, "Vallack install should disable conflicting Home Row Arrows")

        let persisted = await manager.ruleCollectionStore.loadCollections()
        let persistedMods = persisted.first { $0.id == RuleCollectionIdentifier.homeRowMods }
        XCTAssertTrue(persistedMods?.isEnabled ?? false, "Home Row Mods preset should be persisted")
        XCTAssertEqual(
            persistedMods?.configuration.homeRowModsConfig?.modifierAssignments,
            HomeRowModsConfig.vallackTwoRowSplit,
            "Persisted Home Row Mods config should use Vallack top-row modifiers"
        )
    }

    @MainActor
    func testVallackInstallFromDefaultCatalogAppliesWithoutHomeRowArrowConflict() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()

        _ = try await PackInstaller.shared.install(PackRegistry.vallackSystem, manager: manager)

        XCTAssertFalse(
            manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.homeRowArrows }?.isEnabled ?? true,
            "Full-catalog Vallack install should disable Home Row Arrows before regenerating"
        )
        XCTAssertTrue(
            manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.vallackNavigation }?.isEnabled ?? false,
            "Full-catalog Vallack install should enable Vallack navigation"
        )
        XCTAssertEqual(
            manager.ruleCollections
                .first { $0.id == RuleCollectionIdentifier.homeRowMods }?
                .configuration.homeRowModsConfig?.modifierAssignments,
            HomeRowModsConfig.vallackTwoRowSplit
        )
    }

    @MainActor
    func testVallackInstallCreatesSnapshotFile() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        _ = try await PackInstaller.shared.install(
            PackRegistry.vallackSystem,
            manager: manager
        )

        let snapshotURL = PackCollectionSnapshot.snapshotURL(for: PackRegistry.vallackSystem.id)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "Snapshot file should exist after install"
        )
        // Clean up snapshot
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        let data = try Data(contentsOf: snapshotURL)
        XCTAssertFalse(data.isEmpty, "Snapshot file should not be empty")
    }

    @MainActor
    func testVallackUninstallRevertsConfigs() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()

        let snapshotURL = PackCollectionSnapshot.snapshotURL(for: PackRegistry.vallackSystem.id)
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        // Capture pre-install state
        let preModsEnabled = manager.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.homeRowMods }?.isEnabled ?? false
        let preTogglesEnabled = manager.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.homeRowLayerToggles }?.isEnabled ?? false
        if let arrowsIndex = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowArrows }) {
            manager.ruleCollections[arrowsIndex].isEnabled = true
        }

        // Install then uninstall
        _ = try await PackInstaller.shared.install(PackRegistry.vallackSystem, manager: manager)
        try await PackInstaller.shared.uninstall(packID: PackRegistry.vallackSystem.id, manager: manager)

        let collections = manager.ruleCollections

        // Nav layer should be disabled
        let navCollection = collections.first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertFalse(navCollection?.isEnabled ?? true, "Vallack nav should be disabled after uninstall")

        // Home Row Mods should revert to pre-install enabled state
        let modsCollection = collections.first { $0.id == RuleCollectionIdentifier.homeRowMods }
        XCTAssertEqual(
            modsCollection?.isEnabled ?? !preModsEnabled,
            preModsEnabled,
            "Home Row Mods enabled state should revert"
        )

        // Home Row Layer Toggles should revert to pre-install enabled state
        let togglesCollection = collections.first { $0.id == RuleCollectionIdentifier.homeRowLayerToggles }
        XCTAssertEqual(
            togglesCollection?.isEnabled ?? !preTogglesEnabled,
            preTogglesEnabled,
            "Layer Toggles enabled state should revert"
        )

        let arrowsCollection = collections.first { $0.id == RuleCollectionIdentifier.homeRowArrows }
        XCTAssertTrue(arrowsCollection?.isEnabled ?? false, "Home Row Arrows should restore after uninstall")

        // Snapshot file should be cleaned up
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "Snapshot file should be removed after uninstall"
        )

        let persisted = await manager.ruleCollectionStore.loadCollections()
        let persistedNav = persisted.first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertFalse(persistedNav?.isEnabled ?? true, "Persisted Vallack nav should be disabled after uninstall")
    }

    @MainActor
    func testVallackUninstallRestoresHRMWhenPriorArrowStateWouldConflict() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()

        let snapshotURL = PackCollectionSnapshot.snapshotURL(for: PackRegistry.vallackSystem.id)
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        guard let modsIndex = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }),
              let arrowsIndex = manager.ruleCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowArrows })
        else {
            XCTFail("Expected HRM and Home Row Arrows catalog collections")
            return
        }

        var preInstallHRM = HomeRowModsConfig()
        preInstallHRM.holdMode = HomeRowHoldMode.modifiers
        preInstallHRM.enabledKeys = Set(["a", "s", "d", "f", "j", "k", "l", ";"])
        manager.ruleCollections[modsIndex].configuration = .homeRowMods(preInstallHRM)
        manager.ruleCollections[modsIndex].isEnabled = true
        manager.ruleCollections[arrowsIndex].isEnabled = true

        _ = try await PackInstaller.shared.install(PackRegistry.vallackSystem, manager: manager)
        try await PackInstaller.shared.uninstall(packID: PackRegistry.vallackSystem.id, manager: manager)

        let restoredMods = try XCTUnwrap(
            manager.ruleCollections
                .first { $0.id == RuleCollectionIdentifier.homeRowMods }?
                .configuration.homeRowModsConfig
        )
        XCTAssertEqual(restoredMods.enabledKeys, preInstallHRM.enabledKeys)
        XCTAssertEqual(restoredMods.modifierAssignments, preInstallHRM.modifierAssignments)

        let arrowsCollection = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.homeRowArrows }
        XCTAssertFalse(
            arrowsCollection?.isEnabled ?? true,
            "Home Row Arrows should stay disabled when restoring it would conflict with restored HRM"
        )

        let isInstalled = await InstalledPackTracker.shared.isInstalled(packID: PackRegistry.vallackSystem.id)
        XCTAssertFalse(isInstalled, "Vallack install record should be removed after successful uninstall")
        XCTAssertNil(PackCollectionSnapshot.load(for: PackRegistry.vallackSystem.id))
    }

    @MainActor
    func testVallackInstallDoesNotRecordWhenManagedApplyFails() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        try? await InstalledPackTracker.shared.remove(packID: PackRegistry.vallackSystem.id)
        PackCollectionSnapshot.remove(for: PackRegistry.vallackSystem.id)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vallack-apply-fail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.vallackSystem.id)
        }

        // Keep admission/recovery usable; fail the later source-write stage so
        // this still exercises managed-default snapshot rollback and cleanup.
        let blockedSource = tempDir.appendingPathComponent("CustomRules.json")
        try FileManager.default.createDirectory(at: blockedSource, withIntermediateDirectories: true)

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
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()
        let originalCollections = manager.ruleCollections

        do {
            _ = try await PackInstaller.shared.install(PackRegistry.vallackSystem, manager: manager)
            XCTFail("Install should fail when managed defaults cannot be applied")
        } catch let error as PackInstaller.InstallError {
            guard case .saveFailed = error else {
                XCTFail("Expected saveFailed, got \(error)")
                return
            }
        }

        let isInstalled = await InstalledPackTracker.shared.isInstalled(packID: PackRegistry.vallackSystem.id)
        XCTAssertFalse(
            isInstalled,
            "Failed managed install must not record the pack as installed"
        )
        XCTAssertEqual(
            manager.ruleCollections,
            originalCollections,
            "Failed managed install should restore in-memory collections"
        )
        XCTAssertNil(
            PackCollectionSnapshot.load(for: PackRegistry.vallackSystem.id),
            "Failed managed install should not leave an uninstall snapshot behind"
        )
    }

    @MainActor
    func testVallackFailedInstallRestoresModernSnapshotAndRemovesLegacySnapshot() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let packID = PackRegistry.vallackSystem.id
        let modernSnapshotURL = PackCollectionSnapshot.snapshotURL(for: packID)
        let legacySnapshotURL = AppPaths.configDirectory.appendingPathComponent("vallack-system-snapshot.json")
        let originalModernSnapshotData = try? Data(contentsOf: modernSnapshotURL)
        let originalLegacySnapshotData = try? Data(contentsOf: legacySnapshotURL)
        defer {
            try? FileManager.default.removeItem(at: modernSnapshotURL)
            if let originalModernSnapshotData {
                try? FileManager.default.createDirectory(
                    at: modernSnapshotURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? originalModernSnapshotData.write(to: modernSnapshotURL, options: .atomic)
            }

            try? FileManager.default.removeItem(at: legacySnapshotURL)
            if let originalLegacySnapshotData {
                try? FileManager.default.createDirectory(
                    at: legacySnapshotURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? originalLegacySnapshotData.write(to: legacySnapshotURL, options: .atomic)
            }
        }

        let catalog = RuleCollectionCatalog().defaultCollections()
        let previousCollection = try XCTUnwrap(
            catalog.first(where: { $0.id == RuleCollectionIdentifier.homeRowMods })
        )
        let previousSnapshot = try PackCollectionSnapshot(
            packID: packID,
            snapshotDate: Date(timeIntervalSince1970: 126),
            entries: [
                PackCollectionSnapshot.Entry(
                    collectionID: previousCollection.id,
                    wasEnabled: previousCollection.isEnabled,
                    configurationJSON: JSONEncoder().encode(previousCollection.configuration)
                ),
            ]
        )
        try PackCollectionSnapshot.save(previousSnapshot)

        try FileManager.default.createDirectory(
            at: legacySnapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacySnapshotData = try JSONSerialization.data(withJSONObject: [
            "homeRowModsEnabled": true,
            "homeRowLayerTogglesEnabled": false,
        ])
        try legacySnapshotData.write(to: legacySnapshotURL, options: .atomic)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vallack-legacy-rollback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Keep admission/recovery usable; fail the later source-write stage so
        // this still exercises managed-default snapshot rollback and cleanup.
        let blockedSource = tempDir.appendingPathComponent("CustomRules.json")
        try FileManager.default.createDirectory(at: blockedSource, withIntermediateDirectories: true)

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
        manager.ruleCollections = catalog
        let originalRuleState = manager.snapshotRuleState()
        let tracker = InstalledPackTracker(
            fileURL: tempDir.appendingPathComponent("installed-packs.json")
        )

        do {
            _ = try await PackInstaller.shared.install(
                PackRegistry.vallackSystem,
                manager: manager,
                installedPackTracker: tracker
            )
            XCTFail("Install should fail when managed defaults cannot be applied")
        } catch {
            // Expected: the custom-rule source is deliberately unreadable.
        }

        XCTAssertEqual(manager.ruleCollections, originalRuleState.collections)
        XCTAssertEqual(manager.customRules, originalRuleState.customRules)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacySnapshotURL.path),
            "The legacy Vallack migration snapshot should retain its historical rollback cleanup"
        )

        let restoredSnapshot = try XCTUnwrap(PackCollectionSnapshot.load(for: packID))
        XCTAssertEqual(restoredSnapshot.snapshotDate, previousSnapshot.snapshotDate)
        XCTAssertEqual(restoredSnapshot.entries.count, previousSnapshot.entries.count)
        XCTAssertEqual(
            restoredSnapshot.entries.first?.configurationJSON,
            previousSnapshot.entries.first?.configurationJSON
        )
    }

    @MainActor
    func testVallackUninstallWithoutSnapshotDoesNotCrash() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Temporarily remove vallack-system from tracker so the direct
        // toggleCollection call below isn't blocked by the ownership check.
        try? await InstalledPackTracker.shared.remove(packID: PackRegistry.vallackSystem.id)

        // Manually enable the nav collection without going through the installer
        // (simulates a corrupted state where snapshot file is missing)
        _ = await manager.toggleCollection(
            id: RuleCollectionIdentifier.vallackNavigation,
            isEnabled: true,
            autoResolveConflicts: true
        )

        // Register as installed in the tracker (tearDown restores original state)
        try await InstalledPackTracker.shared.upsert(InstalledPackRecord(
            packID: PackRegistry.vallackSystem.id,
            version: PackRegistry.vallackSystem.version
        ))

        // Ensure no snapshot file exists
        let snapshotURL = PackCollectionSnapshot.snapshotURL(for: PackRegistry.vallackSystem.id)
        try? FileManager.default.removeItem(at: snapshotURL)

        // Uninstall should not crash — just skip the revert
        try await PackInstaller.shared.uninstall(
            packID: PackRegistry.vallackSystem.id,
            manager: manager
        )

        let navCollection = manager.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertFalse(navCollection?.isEnabled ?? true, "Nav collection should still be disabled")
    }

    // MARK: - Helpers

    @MainActor
    private func makeTestManager() throws -> (RuleCollectionsManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vallack-test-\(UUID().uuidString)")
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
