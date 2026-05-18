@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class VallackSystemPackTests: XCTestCase {

    // MARK: - Nav Layer Collection

    func testVallackNavigationCollectionExistsInCatalog() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }
        XCTAssertNotNil(collection, "Vallack Navigation collection must exist in catalog")
    }

    func testVallackNavigationHas18Mappings() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }!
        XCTAssertEqual(collection.mappings.count, 18, "Should have 18 key mappings (10 right hand + 8 left hand)")
    }

    func testVallackNavigationTargetsCustomLayer() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }!
        XCTAssertEqual(collection.targetLayer, .custom("vallack-nav"))
    }

    func testVallackNavigationHasNoMomentaryActivator() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }!
        XCTAssertNil(
            collection.momentaryActivator,
            "Activation is handled by homeRowLayerToggles (F/J), not a momentaryActivator"
        )
    }

    func testVallackNavigationIsDisabledByDefault() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }!
        XCTAssertFalse(collection.isEnabled)
        XCTAssertFalse(collection.isSystemDefault)
    }

    func testVallackNavigationContainsExpectedArrowMappings() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }!
        let mappingsByInput = Dictionary(uniqueKeysWithValues: collection.mappings.map { ($0.input, $0) })

        XCTAssertEqual(mappingsByInput["h"]?.action, .keystroke(key: "left"))
        XCTAssertEqual(mappingsByInput["j"]?.action, .keystroke(key: "down"))
        XCTAssertEqual(mappingsByInput["k"]?.action, .keystroke(key: "up"))
        XCTAssertEqual(mappingsByInput["l"]?.action, .keystroke(key: "right"))
    }

    func testVallackNavigationContainsClipboardAndEditing() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }!
        let mappingsByInput = Dictionary(uniqueKeysWithValues: collection.mappings.map { ($0.input, $0) })

        XCTAssertEqual(mappingsByInput["y"]?.action, .keystroke(key: "M-c"), "y should be Copy")
        XCTAssertEqual(mappingsByInput[";"]?.action, .keystroke(key: "M-v"), "; should be Paste")
        XCTAssertEqual(mappingsByInput["u"]?.action, .keystroke(key: "bspc"), "u should be Backspace")
        XCTAssertEqual(mappingsByInput["i"]?.action, .keystroke(key: "ret"), "i should be Enter")
    }

    func testVallackNavigationInputKeysAreUnique() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let collection = catalog.first { $0.id == RuleCollectionIdentifier.vallackNavigation }!
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
        let expectedKeys: Set<String> = ["q", "w", "e", "u", "i", "o"]
        XCTAssertEqual(Set(preset.keys), expectedKeys)
    }

    func testVallackTwoRowSplitMapsToValidModifiers() {
        let validModifiers: Set<String> = ["lctl", "lalt", "lmet", "lsft", "rctl", "ralt", "rmet", "rsft"]
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

        let snapshotURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/keypath/vallack-system-snapshot.json")
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

        let snapshotURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/keypath/vallack-system-snapshot.json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        // Capture pre-install state
        let preModsEnabled = manager.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.homeRowMods }?.isEnabled ?? false
        let preTogglesEnabled = manager.ruleCollections
            .first { $0.id == RuleCollectionIdentifier.homeRowLayerToggles }?.isEnabled ?? false

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

        // Snapshot file should be cleaned up
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "Snapshot file should be removed after uninstall"
        )
    }

    @MainActor
    func testVallackUninstallWithoutSnapshotDoesNotCrash() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Manually enable the nav collection without going through the installer
        // (simulates a corrupted state where snapshot file is missing)
        _ = await manager.toggleCollection(
            id: RuleCollectionIdentifier.vallackNavigation,
            isEnabled: true,
            autoResolveConflicts: true
        )

        // Register as installed in the tracker
        try await InstalledPackTracker.shared.upsert(InstalledPackRecord(
            packID: PackRegistry.vallackSystem.id,
            version: PackRegistry.vallackSystem.version
        ))
        defer {
            Task { try? await InstalledPackTracker.shared.remove(packID: PackRegistry.vallackSystem.id) }
        }

        // Ensure no snapshot file exists
        let snapshotURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/keypath/vallack-system-snapshot.json")
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
