@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
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
    func testCapsLockPackInstallsTheSelectedCatalogConfiguration() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()
        var reloadCallbackCount = 0
        manager.onRulesChanged = { reloadCallbackCount += 1 }

        guard let catalogConfiguration = RuleCollectionCatalog().defaultCollections()
            .first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })?
            .configuration,
            let configuration = FirstSuccessOnboardingWindowController
            .escapeOnlyCapsLockConfiguration(from: catalogConfiguration)
        else {
            return XCTFail("Caps Lock Remap must remain present in the catalog")
        }

        let catalogCapsLock = try XCTUnwrap(
            manager.ruleCollections.first(where: {
                $0.id == RuleCollectionIdentifier.capsLockRemap
            })
        )
        XCTAssertTrue(catalogCapsLock.isEnabled)
        XCTAssertFalse(
            FirstSuccessOnboardingWindowController.capsLockRequiresRulesHandoff(
                existing: catalogCapsLock,
                catalogConfiguration: catalogConfiguration,
                onboardingConfiguration: configuration
            ),
            "The enabled catalog default is untouched first-run state, not a user conflict"
        )

        let record = try await PackInstaller.shared.install(
            PackRegistry.capsLockToEscape,
            collectionConfiguration: configuration,
            manager: manager,
            skipFinalReload: true
        )

        XCTAssertEqual(record.packID, PackRegistry.capsLockToEscape.id)
        let isInstalled = await PackInstaller.shared.isInstalled(packID: PackRegistry.capsLockToEscape.id)
        XCTAssertTrue(isInstalled)

        let capsLock = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertTrue(capsLock?.isEnabled ?? false)
        XCTAssertEqual(capsLock?.configuration, configuration)
        XCTAssertEqual(capsLock?.configuration.tapHoldPickerConfig?.selectedHoldOutput, "caps")
        XCTAssertEqual(reloadCallbackCount, 0)
    }

    @MainActor
    func testFirstSuccessCapsLockConfigurationDoesNotInstallHyperEarly() throws {
        let catalogConfiguration = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })?
                .configuration
        )

        let configuration = try XCTUnwrap(
            FirstSuccessOnboardingWindowController.escapeOnlyCapsLockConfiguration(
                from: catalogConfiguration
            )
        )

        XCTAssertEqual(configuration.tapHoldPickerConfig?.selectedTapOutput, "esc")
        XCTAssertEqual(configuration.tapHoldPickerConfig?.selectedHoldOutput, "caps")
        XCTAssertTrue(configuration.tapHoldPickerConfig?.holdOptions.contains {
            $0.output == "caps"
        } ?? false)
    }

    @MainActor
    func testFirstSuccessCapsStepPreservesLauncherOwnedHyper() throws {
        var launcherOwnedCapsLock = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })
        )
        let catalogConfiguration = try XCTUnwrap(
            launcherOwnedCapsLock.configuration.tapHoldPickerConfig
        )
        launcherOwnedCapsLock.configuration = .tapHoldPicker(TapHoldPickerConfig(
            inputKey: catalogConfiguration.inputKey,
            tapOptions: catalogConfiguration.tapOptions,
            holdOptions: catalogConfiguration.holdOptions,
            selectedTapOutput: "esc",
            selectedHoldOutput: "hyper"
        ))

        XCTAssertTrue(
            FirstSuccessOnboardingWindowController.capsLockAlreadyProvidesFirstWin(
                existing: launcherOwnedCapsLock,
                quickLauncherInstalled: true
            )
        )
        XCTAssertFalse(
            FirstSuccessOnboardingWindowController.capsLockAlreadyProvidesFirstWin(
                existing: launcherOwnedCapsLock,
                quickLauncherInstalled: false
            )
        )
    }

    @MainActor
    func testFirstSuccessPreservesCustomizedCapsLockConfiguration() throws {
        let catalogCapsLock = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })
        )
        let onboardingConfiguration = try XCTUnwrap(
            FirstSuccessOnboardingWindowController.escapeOnlyCapsLockConfiguration(
                from: catalogCapsLock.configuration
            )
        )
        var customizedCapsLock = catalogCapsLock
        customizedCapsLock.configuration.updateSelectedTapOutput("bspc")

        XCTAssertTrue(
            FirstSuccessOnboardingWindowController.capsLockRequiresRulesHandoff(
                existing: customizedCapsLock,
                catalogConfiguration: catalogCapsLock.configuration,
                onboardingConfiguration: onboardingConfiguration
            )
        )
    }

    @MainActor
    func testHyperStepPreservesDisabledCustomizedCapsLockConfiguration() throws {
        let catalogCapsLock = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })
        )
        let escapeConfiguration = try XCTUnwrap(
            FirstSuccessOnboardingWindowController.escapeOnlyCapsLockConfiguration(
                from: catalogCapsLock.configuration
            )
        )
        let hyperConfiguration = try XCTUnwrap(
            PackRegistry.launcher.managedDefaults
                .first(where: { $0.collectionID == RuleCollectionIdentifier.capsLockRemap })?
                .defaultConfiguration
        )
        var customizedCapsLock = catalogCapsLock
        customizedCapsLock.isEnabled = false
        customizedCapsLock.configuration.updateSelectedTapOutput("bspc")

        XCTAssertTrue(
            FirstSuccessOnboardingWindowController.capsLockRequiresHyperRulesHandoff(
                existing: customizedCapsLock,
                catalogConfiguration: catalogCapsLock.configuration,
                escapeConfiguration: escapeConfiguration,
                hyperConfiguration: hyperConfiguration
            )
        )
    }

    @MainActor
    func testOnboardingCapsInstallNeverSilentlyDisablesAConflictingRule() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()

        let catalogCapsLock = try XCTUnwrap(
            manager.ruleCollections.first(where: {
                $0.id == RuleCollectionIdentifier.capsLockRemap
            })
        )
        let onboardingConfiguration = try XCTUnwrap(
            FirstSuccessOnboardingWindowController.escapeOnlyCapsLockConfiguration(
                from: catalogCapsLock.configuration
            )
        )
        let existingRule = CustomRule(
            input: "caps",
            action: .keystroke(key: "tab"),
            isEnabled: true
        )
        manager.customRules = [existingRule]

        XCTAssertTrue(
            FirstSuccessOnboardingWindowController.onboardingConfigurationConflicts(
                manager: manager,
                collectionID: RuleCollectionIdentifier.capsLockRemap,
                configuration: onboardingConfiguration
            )
        )

        var conflictPromptCount = 0
        manager.onConflictResolution = { _ in
            conflictPromptCount += 1
            return .keepExisting
        }
        let tracker = InstalledPackTracker(
            fileURL: tempDir.appendingPathComponent("installed-packs.json")
        )

        do {
            _ = try await PackInstaller.shared.install(
                PackRegistry.capsLockToEscape,
                collectionConfiguration: onboardingConfiguration,
                autoResolveCollectionConflicts: false,
                manager: manager,
                skipFinalReload: true,
                installedPackTracker: tracker
            )
            XCTFail("Keeping the existing rule should cancel the onboarding install")
        } catch {
            // Expected: the explicit conflict choice preserves current behavior.
        }

        XCTAssertEqual(conflictPromptCount, 1)
        XCTAssertTrue(manager.customRules.first(where: { $0.id == existingRule.id })?.isEnabled ?? false)
        XCTAssertEqual(
            manager.ruleCollections.first(where: {
                $0.id == RuleCollectionIdentifier.capsLockRemap
            }),
            catalogCapsLock
        )
        let isInstalled = await tracker.isInstalled(packID: PackRegistry.capsLockToEscape.id)
        XCTAssertFalse(isInstalled)
    }

    @MainActor
    func testVisualOnlyInstallRestoresPriorTrackerStateWhenTrackerWriteFails() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let trackerURL = tempDir.appendingPathComponent("visual-installed-packs.json")
        let failingTracker = InstalledPackTracker(fileURL: trackerURL)
        let previousRecord = InstalledPackRecord(
            packID: PackRegistry.keystrokeHistory.id,
            version: "0.9.0",
            installedAt: Date(timeIntervalSince1970: 21),
            quickSettingValues: [:]
        )
        try await failingTracker.upsert(previousRecord)
        try FileManager.default.removeItem(at: trackerURL)
        try FileManager.default.createDirectory(
            at: trackerURL,
            withIntermediateDirectories: true
        )

        do {
            _ = try await PackInstaller.shared.install(
                PackRegistry.keystrokeHistory,
                manager: manager,
                installedPackTracker: failingTracker
            )
            XCTFail("Expected tracker persistence to fail")
        } catch let error as PackInstaller.InstallError {
            guard case let .saveFailed(reason) = error else {
                return XCTFail("Expected saveFailed, got \(error)")
            }
            XCTAssertEqual(
                reason,
                "visual-only installed-pack record could not be saved and the previous state could not be fully restored"
            )
        } catch {
            XCTFail("Expected full-restore saveFailed, got \(error)")
        }

        let restoredRecord = await failingTracker.record(
            for: PackRegistry.keystrokeHistory.id
        )
        XCTAssertEqual(restoredRecord, previousRecord)
    }

    @MainActor
    func testPlainPackInstallRestoresRuleAndTrackerStateWhenTrackerWriteFails() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingRule = CustomRule(
            input: "f20",
            action: .keystroke(key: "f19")
        )
        manager.customRules = [existingRule]
        let originalRuleState = manager.snapshotRuleState()
        let didGenerateOriginalConfig = await manager.regenerateConfigFromCollections(
            skipReload: true
        )
        XCTAssertTrue(didGenerateOriginalConfig)

        let configURL = URL(fileURLWithPath: manager.configurationService.configurationPath)
        let collectionStoreURL = tempDir.appendingPathComponent("RuleCollections.json")
        let customRulesStoreURL = tempDir.appendingPathComponent("CustomRules.json")
        let originalConfigData = try Data(contentsOf: configURL)
        let originalCollectionStoreData = try Data(contentsOf: collectionStoreURL)
        let originalCustomRulesStoreData = try Data(contentsOf: customRulesStoreURL)

        let pack = Pack(
            id: "com.keypath.test.plain-pack-rollback",
            version: "1.0.0",
            name: "Plain Pack Rollback",
            tagline: "Exercises tracker rollback",
            shortDescription: "Test-only pack",
            longDescription: "",
            category: "Test",
            iconSymbol: "testtube.2",
            bindings: [
                PackBindingTemplate(
                    input: "f13",
                    output: "f14",
                    title: "F13 → F14"
                ),
            ]
        )

        let trackerURL = tempDir.appendingPathComponent("plain-installed-packs.json")
        let failingTracker = InstalledPackTracker(fileURL: trackerURL)
        let previousRecord = InstalledPackRecord(
            packID: pack.id,
            version: "0.9.0",
            installedAt: Date(timeIntervalSince1970: 42),
            quickSettingValues: [:]
        )
        try await failingTracker.upsert(previousRecord)
        try FileManager.default.removeItem(at: trackerURL)
        try FileManager.default.createDirectory(
            at: trackerURL,
            withIntermediateDirectories: true
        )

        do {
            _ = try await PackInstaller.shared.install(
                pack,
                manager: manager,
                skipFinalReload: true,
                installedPackTracker: failingTracker
            )
            XCTFail("Expected tracker persistence to fail")
        } catch let error as PackInstaller.InstallError {
            guard case let .saveFailed(reason) = error else {
                return XCTFail("Expected saveFailed, got \(error)")
            }
            XCTAssertEqual(
                reason,
                "installed-pack record could not be saved and the previous state could not be fully restored"
            )
        } catch {
            XCTFail("Expected full-restore saveFailed, got \(error)")
        }

        XCTAssertEqual(manager.snapshotRuleState().collections, originalRuleState.collections)
        XCTAssertEqual(manager.snapshotRuleState().customRules, originalRuleState.customRules)
        XCTAssertEqual(try Data(contentsOf: configURL), originalConfigData)
        XCTAssertEqual(
            try Data(contentsOf: collectionStoreURL),
            originalCollectionStoreData
        )
        XCTAssertEqual(
            try Data(contentsOf: customRulesStoreURL),
            originalCustomRulesStoreData
        )
        let restoredRecord = await failingTracker.record(for: pack.id)
        XCTAssertEqual(restoredRecord, previousRecord)
    }

    @MainActor
    func testCollectionBackedInstallRestoresRuleStateWhenTrackerWriteFails() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        guard var capsLock = RuleCollectionCatalog().defaultCollections()
            .first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })
        else {
            return XCTFail("Caps Lock Remap must remain present in the catalog")
        }
        capsLock.isEnabled = false
        manager.ruleCollections = [capsLock]
        let originalCollections = manager.ruleCollections

        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let unwritableTrackerURL = tempDir.appendingPathComponent("installed-packs-is-a-directory")
        try FileManager.default.createDirectory(
            at: unwritableTrackerURL,
            withIntermediateDirectories: true
        )
        let failingTracker = InstalledPackTracker(fileURL: unwritableTrackerURL)

        var configuration = capsLock.configuration
        configuration.updateSelectedTapOutput("esc")

        do {
            _ = try await PackInstaller.shared.install(
                PackRegistry.capsLockToEscape,
                collectionConfiguration: configuration,
                manager: manager,
                installedPackTracker: failingTracker
            )
            XCTFail("Expected tracker persistence to fail")
        } catch let error as PackInstaller.InstallError {
            guard case let .saveFailed(reason) = error else {
                return XCTFail("Expected saveFailed, got \(error)")
            }
            XCTAssertEqual(
                reason,
                "installed-pack record could not be saved and the previous state could not be fully restored"
            )
        } catch {
            XCTFail("Expected full-restore saveFailed, got \(error)")
        }

        XCTAssertEqual(manager.ruleCollections, originalCollections)
        XCTAssertEqual(regenerationCount, 2, "Install and rollback should each regenerate once")
        let isInstalled = await failingTracker.isInstalled(packID: PackRegistry.capsLockToEscape.id)
        XCTAssertFalse(isInstalled, "A failed install must not remain authoritative in memory")
    }

    @MainActor
    func testSystemPackInstallRestoresPriorStateWhenTrackerWriteFails() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        let originalManagedSnapshot = PackCollectionSnapshot.load(for: PackRegistry.launcher.id)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            if let originalManagedSnapshot {
                try? PackCollectionSnapshot.save(originalManagedSnapshot)
            } else {
                PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
            }
        }

        let catalog = RuleCollectionCatalog().defaultCollections()
        guard var customCaps = catalog.first(where: {
            $0.id == RuleCollectionIdentifier.capsLockRemap
        }) else {
            return XCTFail("Caps Lock Remap must remain present in the catalog")
        }
        customCaps.configuration = .tapHoldPicker(TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: customCaps.configuration.tapHoldPickerConfig?.tapOptions ?? [],
            holdOptions: customCaps.configuration.tapHoldPickerConfig?.holdOptions ?? [],
            selectedTapOutput: "bspc",
            selectedHoldOutput: "lctl"
        ))
        customCaps.isEnabled = true
        manager.ruleCollections = [customCaps]
        let originalRuleState = manager.snapshotRuleState()

        var regenerationCount = 0
        manager.onBeforeSave = { regenerationCount += 1 }

        let previousSnapshot = try PackCollectionSnapshot(
            packID: PackRegistry.launcher.id,
            snapshotDate: Date(timeIntervalSince1970: 42),
            entries: [
                PackCollectionSnapshot.Entry(
                    collectionID: RuleCollectionIdentifier.capsLockRemap,
                    wasEnabled: true,
                    configurationJSON: JSONEncoder().encode(customCaps.configuration)
                ),
            ]
        )
        try PackCollectionSnapshot.save(previousSnapshot)

        let trackerURL = tempDir.appendingPathComponent("system-installed-packs.json")
        let failingTracker = InstalledPackTracker(fileURL: trackerURL)
        let previousRecord = InstalledPackRecord(
            packID: PackRegistry.launcher.id,
            version: "0.9.0",
            installedAt: Date(timeIntervalSince1970: 42),
            quickSettingValues: [:]
        )
        try await failingTracker.upsert(previousRecord)
        try FileManager.default.removeItem(at: trackerURL)
        try FileManager.default.createDirectory(
            at: trackerURL,
            withIntermediateDirectories: true
        )

        do {
            _ = try await PackInstaller.shared.install(
                PackRegistry.launcher,
                managedDefaultPolicy: .useRecommended,
                manager: manager,
                installedPackTracker: failingTracker
            )
            XCTFail("Expected tracker persistence to fail")
        } catch let error as PackInstaller.InstallError {
            guard case let .saveFailed(reason) = error else {
                return XCTFail("Expected saveFailed, got \(error)")
            }
            XCTAssertEqual(
                reason,
                "installed-pack record could not be saved and the previous system-pack state could not be fully restored"
            )
        } catch {
            XCTFail("Expected full-restore saveFailed, got \(error)")
        }

        XCTAssertEqual(manager.ruleCollections, originalRuleState.collections)
        XCTAssertEqual(manager.customRules, originalRuleState.customRules)
        XCTAssertEqual(regenerationCount, 2, "Install and rollback should each regenerate once")
        let restoredRecord = await failingTracker.record(for: PackRegistry.launcher.id)
        XCTAssertEqual(restoredRecord, previousRecord)

        let restoredSnapshot = PackCollectionSnapshot.load(for: PackRegistry.launcher.id)
        XCTAssertEqual(restoredSnapshot?.snapshotDate, previousSnapshot.snapshotDate)
        XCTAssertEqual(restoredSnapshot?.entries.count, previousSnapshot.entries.count)
        XCTAssertEqual(
            restoredSnapshot?.entries.first?.configurationJSON,
            previousSnapshot.entries.first?.configurationJSON
        )
    }

    @MainActor
    func testSystemPackInstallRestoresDurableStateWhenCollectionStoreWriteFails() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        let originalManagedSnapshot = PackCollectionSnapshot.load(for: PackRegistry.launcher.id)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            if let originalManagedSnapshot {
                try? PackCollectionSnapshot.save(originalManagedSnapshot)
            } else {
                PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
            }
        }

        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()
        let originalRuleState = manager.snapshotRuleState()
        let didGenerateOriginalConfig = await manager.regenerateConfigFromCollections(skipReload: true)
        XCTAssertTrue(didGenerateOriginalConfig)

        let configURL = URL(fileURLWithPath: manager.configurationService.configurationPath)
        let collectionStoreURL = tempDir.appendingPathComponent("RuleCollections.json")
        let customRulesStoreURL = tempDir.appendingPathComponent("CustomRules.json")
        let originalConfigData = try Data(contentsOf: configURL)
        let originalCollectionStoreData = try Data(contentsOf: collectionStoreURL)
        let originalCustomRulesStoreData = try Data(contentsOf: customRulesStoreURL)

        let previousSnapshot = try PackCollectionSnapshot(
            packID: PackRegistry.launcher.id,
            snapshotDate: Date(timeIntervalSince1970: 84),
            entries: [
                PackCollectionSnapshot.Entry(
                    collectionID: RuleCollectionIdentifier.capsLockRemap,
                    wasEnabled: true,
                    configurationJSON: JSONEncoder().encode(
                        originalRuleState.collections.first(where: {
                            $0.id == RuleCollectionIdentifier.capsLockRemap
                        })?.configuration ?? .list
                    )
                ),
            ]
        )
        try PackCollectionSnapshot.save(previousSnapshot)

        let tracker = InstalledPackTracker(
            fileURL: tempDir.appendingPathComponent("system-installed-packs.json")
        )
        let previousRecord = InstalledPackRecord(
            packID: PackRegistry.launcher.id,
            version: "0.8.0",
            installedAt: Date(timeIntervalSince1970: 84),
            quickSettingValues: [:]
        )
        try await tracker.upsert(previousRecord)

        try FileManager.default.removeItem(at: collectionStoreURL)
        try FileManager.default.createDirectory(
            at: collectionStoreURL,
            withIntermediateDirectories: false
        )
        var shouldRemoveFailedStore = true
        manager.onError = { _ in
            // Make this a one-shot persistence failure so the compensating
            // rollback can prove it rewrites every durable representation.
            guard shouldRemoveFailedStore else { return }
            shouldRemoveFailedStore = false
            try? FileManager.default.removeItem(at: collectionStoreURL)
        }

        do {
            _ = try await PackInstaller.shared.install(
                PackRegistry.launcher,
                managedDefaultPolicy: .useRecommended,
                manager: manager,
                skipFinalReload: true,
                installedPackTracker: tracker
            )
            XCTFail("Expected the collection-store write to fail")
        } catch {
            // Expected: the first collection-store write targets a directory.
        }

        let restoredRuleState = manager.snapshotRuleState()
        XCTAssertEqual(restoredRuleState.collections, originalRuleState.collections)
        XCTAssertEqual(restoredRuleState.customRules, originalRuleState.customRules)
        XCTAssertEqual(try Data(contentsOf: configURL), originalConfigData)
        XCTAssertEqual(
            try Data(contentsOf: collectionStoreURL),
            originalCollectionStoreData
        )
        XCTAssertEqual(
            try Data(contentsOf: customRulesStoreURL),
            originalCustomRulesStoreData
        )
        let restoredRecord = await tracker.record(for: PackRegistry.launcher.id)
        XCTAssertEqual(restoredRecord, previousRecord)

        let restoredSnapshot = PackCollectionSnapshot.load(for: PackRegistry.launcher.id)
        XCTAssertEqual(restoredSnapshot?.snapshotDate, previousSnapshot.snapshotDate)
        XCTAssertEqual(
            restoredSnapshot?.entries.first?.configurationJSON,
            previousSnapshot.entries.first?.configurationJSON
        )
    }

    @MainActor
    func testQuickLauncherBuildsOnTheCatalogCapsLockInstall() async throws {
        TestEnvironment.forceTestMode = true
        defer { TestEnvironment.forceTestMode = false }

        let (manager, tempDir) = try makeTestManager()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            PackCollectionSnapshot.remove(for: PackRegistry.launcher.id)
        }
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()
        var reloadCallbackCount = 0
        manager.onRulesChanged = { reloadCallbackCount += 1 }

        guard let catalogConfiguration = RuleCollectionCatalog().defaultCollections()
            .first(where: { $0.id == RuleCollectionIdentifier.capsLockRemap })?
            .configuration,
            let configuration = FirstSuccessOnboardingWindowController
            .escapeOnlyCapsLockConfiguration(from: catalogConfiguration)
        else {
            return XCTFail("Caps Lock Remap must remain present in the catalog")
        }

        let launcherCatalogConfiguration = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first(where: { $0.id == RuleCollectionIdentifier.launcher })?
                .configuration
        )
        let emptyLauncherConfiguration = try XCTUnwrap(
            FirstSuccessOnboardingWindowController.emptyQuickLauncherConfiguration(
                from: launcherCatalogConfiguration
            )
        )

        _ = try await PackInstaller.shared.install(
            PackRegistry.capsLockToEscape,
            collectionConfiguration: configuration,
            manager: manager,
            skipFinalReload: true
        )
        XCTAssertEqual(
            manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }?
                .configuration.tapHoldPickerConfig?.selectedHoldOutput,
            "caps"
        )
        _ = try await PackInstaller.shared.install(
            PackRegistry.launcher,
            collectionConfiguration: emptyLauncherConfiguration,
            managedDefaultPolicy: .useRecommended,
            manager: manager,
            skipFinalReload: true
        )

        let capsLock = manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.capsLockRemap }
        XCTAssertTrue(capsLock?.isEnabled ?? false)
        XCTAssertEqual(capsLock?.configuration.tapHoldPickerConfig?.selectedTapOutput, "esc")
        XCTAssertEqual(capsLock?.configuration.tapHoldPickerConfig?.selectedHoldOutput, "hyper")
        let launcher = manager.ruleCollections.first {
            $0.id == RuleCollectionIdentifier.launcher
        }
        XCTAssertTrue(launcher?.isEnabled ?? false)
        XCTAssertEqual(launcher?.configuration, emptyLauncherConfiguration)
        XCTAssertEqual(launcher?.configuration.launcherGridConfig?.mappings, [])

        let installedCapsLock = await PackInstaller.shared.isInstalled(packID: PackRegistry.capsLockToEscape.id)
        let installedLauncher = await PackInstaller.shared.isInstalled(packID: PackRegistry.launcher.id)
        XCTAssertTrue(installedCapsLock)
        XCTAssertTrue(installedLauncher)
        XCTAssertEqual(reloadCallbackCount, 0)
    }

    @MainActor
    func testFirstSuccessAppendsToCustomizedQuickLauncherConfiguration() throws {
        let launcherCatalog = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first(where: { $0.id == RuleCollectionIdentifier.launcher })
        )
        var customGrid = try XCTUnwrap(launcherCatalog.configuration.launcherGridConfig)
        customGrid.activationMode = .leaderSequence
        customGrid.hyperTriggerMode = .tap
        customGrid.mappings = [
            LauncherMapping(
                key: "q",
                action: .launchApp(name: "Notes", bundleId: "com.apple.Notes")
            ),
        ]
        let added = LauncherMapping(
            key: "s",
            action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")
        )

        let result = try XCTUnwrap(
            FirstSuccessOnboardingWindowController.launcherConfiguration(
                appending: added,
                to: .launcherGrid(customGrid)
            )
        )

        XCTAssertEqual(result.activationMode, .leaderSequence)
        XCTAssertEqual(result.hyperTriggerMode, .tap)
        XCTAssertEqual(result.mappings.first, customGrid.mappings.first)
        XCTAssertEqual(result.mappings.last?.key, "s")
        XCTAssertEqual(result.mappings.last?.action, added.action)
        XCTAssertTrue(result.hasSeenWelcome)
    }

    @MainActor
    func testEnabledCatalogLauncherStartsFirstSuccessWithoutSampleMappings() throws {
        let catalogLauncher = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first(where: { $0.id == RuleCollectionIdentifier.launcher })
        )
        XCTAssertTrue(catalogLauncher.isEnabled)
        XCTAssertFalse(
            FirstSuccessOnboardingWindowController.shouldPreserveLauncherConfiguration(
                existing: catalogLauncher,
                catalogConfiguration: catalogLauncher.configuration
            )
        )
        XCTAssertEqual(
            FirstSuccessOnboardingWindowController.occupiedLauncherKeys(
                existing: catalogLauncher,
                catalogConfiguration: catalogLauncher.configuration
            ),
            []
        )

        let onboardingConfiguration = try XCTUnwrap(
            FirstSuccessOnboardingWindowController.emptyQuickLauncherConfiguration(
                from: catalogLauncher.configuration
            )?.launcherGridConfig
        )
        XCTAssertEqual(onboardingConfiguration.mappings, [])
        XCTAssertEqual(onboardingConfiguration.activationMode, .holdHyper)
        XCTAssertEqual(onboardingConfiguration.hyperTriggerMode, .hold)
    }

    @MainActor
    func testCustomizedLauncherWithDifferentGestureCannotClaimHyperReadiness() throws {
        let catalogLauncher = try XCTUnwrap(
            RuleCollectionCatalog().defaultCollections()
                .first(where: { $0.id == RuleCollectionIdentifier.launcher })
        )
        var customizedLauncher = catalogLauncher
        var customizedConfiguration = try XCTUnwrap(
            customizedLauncher.configuration.launcherGridConfig
        )
        customizedConfiguration.activationMode = .leaderSequence
        customizedConfiguration.hyperTriggerMode = .tap
        customizedLauncher.configuration = .launcherGrid(customizedConfiguration)

        XCTAssertTrue(
            FirstSuccessOnboardingWindowController.shouldPreserveLauncherConfiguration(
                existing: customizedLauncher,
                catalogConfiguration: catalogLauncher.configuration
            )
        )
        XCTAssertFalse(
            FirstSuccessOnboardingWindowController.launcherUsesTaughtHyperGesture(
                customizedLauncher.configuration
            )
        )
        XCTAssertTrue(
            FirstSuccessOnboardingWindowController.customizedLauncherBlocksTaughtHyperGesture(
                existing: customizedLauncher,
                catalogConfiguration: catalogLauncher.configuration
            )
        )
    }

    @MainActor
    func testFirstSuccessDoesNotReplaceAnOccupiedLauncherKey() {
        var launcher = LauncherGridConfig(
            mappings: [
                LauncherMapping(
                    key: "q",
                    action: .launchApp(name: "Notes", bundleId: "com.apple.Notes")
                ),
            ]
        )
        launcher.hasSeenWelcome = true

        XCTAssertNil(
            FirstSuccessOnboardingWindowController.launcherConfiguration(
                appending: LauncherMapping(
                    key: "Q",
                    action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")
                ),
                to: .launcherGrid(launcher)
            )
        )
    }

    @MainActor
    func testFirstSuccessRetriesByReplacingItsSavedLauncherMapping() throws {
        let mappingID = UUID()
        let savedMapping = LauncherMapping(
            id: mappingID,
            key: "q",
            action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")
        )
        let replacement = LauncherMapping(
            id: mappingID,
            key: "s",
            action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")
        )
        let launcher = LauncherGridConfig(mappings: [savedMapping])

        let result = try XCTUnwrap(
            FirstSuccessOnboardingWindowController.launcherConfiguration(
                appending: replacement,
                to: .launcherGrid(launcher)
            )
        )

        XCTAssertEqual(result.mappings.count, 1)
        XCTAssertEqual(result.mappings.first?.id, mappingID)
        XCTAssertEqual(result.mappings.first?.key, "s")
        XCTAssertEqual(result.mappings.first?.action, replacement.action)
    }

    @MainActor
    func testFirstSuccessRetryCanChangeTheAppWithoutCollidingWithItsOwnKey() throws {
        let mappingID = UUID()
        let savedMapping = LauncherMapping(
            id: mappingID,
            key: "q",
            action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")
        )
        let replacement = LauncherMapping(
            id: mappingID,
            key: "q",
            action: .launchApp(name: "Notes", bundleId: "com.apple.Notes")
        )

        let result = try XCTUnwrap(
            FirstSuccessOnboardingWindowController.launcherConfiguration(
                appending: replacement,
                to: .launcherGrid(LauncherGridConfig(mappings: [savedMapping]))
            )
        )

        XCTAssertEqual(result.mappings.count, 1)
        XCTAssertEqual(result.mappings.first, replacement)
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

    @MainActor
    func testUseRecommendedManagedDefaultPolicyBypassesCustomizationPrompt() async throws {
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

        let catalog = RuleCollectionCatalog().defaultCollections()
        guard var customCaps = catalog.first(where: {
            $0.id == RuleCollectionIdentifier.capsLockRemap
        }) else {
            return XCTFail("Caps Lock Remap must remain present in the catalog")
        }
        customCaps.configuration = .tapHoldPicker(TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: customCaps.configuration.tapHoldPickerConfig?.tapOptions ?? [],
            holdOptions: customCaps.configuration.tapHoldPickerConfig?.holdOptions ?? [],
            selectedTapOutput: "bspc",
            selectedHoldOutput: "lctl"
        ))
        customCaps.isEnabled = true
        manager.ruleCollections.append(customCaps)

        _ = try await PackInstaller.shared.install(
            PackRegistry.launcher,
            managedDefaultPolicy: .useRecommended,
            manager: manager
        )

        let capsCollection = manager.ruleCollections.first {
            $0.id == RuleCollectionIdentifier.capsLockRemap
        }
        XCTAssertEqual(capsCollection?.configuration.tapHoldPickerConfig?.selectedTapOutput, "esc")
        XCTAssertEqual(capsCollection?.configuration.tapHoldPickerConfig?.selectedHoldOutput, "hyper")
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

    // MARK: - Display Settings Diff

    func testTapHoldPickerDisplaySettingsDiff() {
        let current = RuleCollectionConfiguration.tapHoldPicker(TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [
                SingleKeyPreset(output: "hyper", label: "✦ Hyper", description: "", icon: ""),
                SingleKeyPreset(output: "esc", label: "⎋ Escape", description: "", icon: ""),
            ],
            holdOptions: [
                SingleKeyPreset(output: "hyper", label: "✦ Hyper", description: "", icon: ""),
                SingleKeyPreset(output: "meh", label: "◇ Meh", description: "", icon: ""),
            ],
            selectedTapOutput: "hyper",
            selectedHoldOutput: "hyper"
        ))

        let proposed = RuleCollectionConfiguration.tapHoldPicker(TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [
                SingleKeyPreset(output: "hyper", label: "✦ Hyper", description: "", icon: ""),
                SingleKeyPreset(output: "esc", label: "⎋ Escape", description: "", icon: ""),
            ],
            holdOptions: [
                SingleKeyPreset(output: "hyper", label: "✦ Hyper", description: "", icon: ""),
                SingleKeyPreset(output: "meh", label: "◇ Meh", description: "", icon: ""),
            ],
            selectedTapOutput: "esc",
            selectedHoldOutput: "hyper"
        ))

        let diffs = RuleCollectionConfiguration.diffSettings(current: current, proposed: proposed)
        XCTAssertEqual(diffs.count, 1, "Only tap action differs")
        XCTAssertEqual(diffs.first?.label, "Tap Action")
        XCTAssertEqual(diffs.first?.current, "✦ Hyper")
        XCTAssertEqual(diffs.first?.proposed, "⎋ Escape")
    }

    func testIdenticalConfigsProduceNoDiff() {
        let config = RuleCollectionConfiguration.tapHoldPicker(TapHoldPickerConfig(
            inputKey: "caps",
            tapOptions: [SingleKeyPreset(output: "esc", label: "⎋ Escape", description: "", icon: "")],
            holdOptions: [SingleKeyPreset(output: "hyper", label: "✦ Hyper", description: "", icon: "")],
            selectedTapOutput: "esc",
            selectedHoldOutput: "hyper"
        ))

        let diffs = RuleCollectionConfiguration.diffSettings(current: config, proposed: config)
        XCTAssertTrue(diffs.isEmpty, "Identical configs should produce no diffs")
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
