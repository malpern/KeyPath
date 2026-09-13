import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class DurableConfigPreferenceRecoveryTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        TestEnvironment.forceTestMode = true
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DurableConfigPreferenceRecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "DurableConfigPreferenceRecovery.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        TestEnvironment.forceTestMode = false
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    func testInterruptedWriteRestoresLeaderFromAnotherDefaultsInstance() throws {
        let files = try initialFiles()
        let before = LeaderKeyPreference.default
        let after = LeaderKeyPreference(key: "f18", targetLayer: .navigation, enabled: true)
        try defaults.set(JSONEncoder().encode(before), forKey: PreferencesService.leaderKeyPreferenceKey)
        _ = try stage(files: files, leader: after)

        let recoveryDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertTrue(try RecoverableRuleWrite.recover(
            files: files, directory: directory, preferences: recoveryDefaults
        ))
        XCTAssertEqual(try storedLeader(recoveryDefaults), before)
        XCTAssertEqual(try Data(contentsOf: files["config"]!), Data("before-config".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testInterruptedCLIRawWriteRestoresCanonicalLeaderAndConfig() throws {
        let config = directory.appendingPathComponent("keypath.kbd")
        try RecoverableRuleWrite.durableWrite(Data("before-config".utf8), config)
        let before = LeaderKeyPreference.default
        let after = LeaderKeyPreference(key: "tab", targetLayer: .navigation, enabled: true)
        let beforeData = try JSONEncoder().encode(before)
        defaults.set(beforeData, forKey: PreferencesService.leaderKeyPreferenceKey)

        _ = try RecoverableRuleWrite.stage(
            files: ["config": config], contents: ["config": Data("after-config".utf8)],
            directory: directory, scope: .rawConfig, preferences: defaults,
            preferenceChanges: [.leader(before: beforeData, after: JSONEncoder().encode(after))]
        )

        let recoveryDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertTrue(try RecoverableRuleWrite.recover(
            files: ["config": config], directory: directory, scope: .rawConfig,
            preferences: recoveryDefaults
        ))
        XCTAssertEqual(try storedLeader(recoveryDefaults), before)
        XCTAssertEqual(try Data(contentsOf: config), Data("before-config".utf8))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: RecoverableRuleWrite.journalURL(directory, scope: .rawConfig).path
        ))
    }

    func testTrackedLeaderConflictLeavesFilesAndJournalForDiagnosis() throws {
        let files = try initialFiles()
        try defaults.set(JSONEncoder().encode(LeaderKeyPreference.default),
                         forKey: PreferencesService.leaderKeyPreferenceKey)
        _ = try stage(
            files: files,
            leader: LeaderKeyPreference(key: "f18", targetLayer: .navigation, enabled: true)
        )
        try defaults.set(
            JSONEncoder().encode(LeaderKeyPreference(key: "f17", targetLayer: .navigation, enabled: true)),
            forKey: PreferencesService.leaderKeyPreferenceKey
        )

        XCTAssertThrowsError(
            try RecoverableRuleWrite.recover(files: files, directory: directory, preferences: defaults)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains(PreferencesService.leaderKeyPreferenceKey))
        }
        XCTAssertEqual(try Data(contentsOf: files["config"]!), Data("after-config".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testPreferenceChangeDuringFileWritesIsNotOverwritten() throws {
        let files = try initialFiles()
        let before = LeaderKeyPreference.default
        let attempted = LeaderKeyPreference(key: "f18", targetLayer: .navigation, enabled: true)
        let newer = LeaderKeyPreference(key: "f17", targetLayer: .navigation, enabled: true)
        try defaults.set(JSONEncoder().encode(before), forKey: PreferencesService.leaderKeyPreferenceKey)
        var writes = 0

        XCTAssertThrowsError(try RecoverableRuleWrite.stage(
            files: files,
            contents: Dictionary(uniqueKeysWithValues: files.map { ($0.key, Data("after-\($0.key)".utf8)) }),
            directory: directory,
            scope: .rules,
            preferences: defaults,
            preferenceChanges: [.leader(
                before: defaults.data(forKey: PreferencesService.leaderKeyPreferenceKey),
                after: JSONEncoder().encode(attempted)
            )],
            writeFile: { data, url in
                writes += 1
                try RecoverableRuleWrite.durableWrite(data, url)
                if writes == 1 {
                    try self.defaults.set(JSONEncoder().encode(newer),
                                          forKey: PreferencesService.leaderKeyPreferenceKey)
                }
            }
        ))
        XCTAssertEqual(try storedLeader(defaults), newer)
        XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testCommittedJournalCleanupDoesNotRejectNewerLeader() throws {
        let files = try initialFiles()
        let committed = LeaderKeyPreference(key: "f18", targetLayer: .navigation, enabled: true)
        let newer = LeaderKeyPreference(key: "f17", targetLayer: .navigation, enabled: true)
        _ = try stage(files: files, leader: committed)
        let pendingData = try Data(contentsOf: RecoverableRuleWrite.journalURL(directory))
        var journal = try JSONDecoder().decode(RecoverableRuleWrite.Journal.self, from: pendingData)
        journal.committed = true
        try RecoverableRuleWrite.durableWrite(
            JSONEncoder().encode(journal), RecoverableRuleWrite.journalURL(directory)
        )
        try defaults.set(JSONEncoder().encode(newer), forKey: PreferencesService.leaderKeyPreferenceKey)

        XCTAssertTrue(try RecoverableRuleWrite.recover(files: files, directory: directory, preferences: defaults))
        XCTAssertEqual(try storedLeader(defaults), newer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    @MainActor
    func testLeaderCandidateIsNotPersistedWhenStagingFailsBeforeJournal() async throws {
        let blocked = directory.appendingPathComponent("blocked")
        try Data("not-a-directory".utf8).write(to: blocked)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(configDirectory: blocked.path, ruleCollectionStore: collections, customRulesStore: rules)
        let preferences = PreferencesService(leaderDefaults: defaults)
        preferences.leaderKeyPreference = .default
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collections, customRulesStore: rules,
            configurationService: service, keymapPreferences: defaults,
            preferencesService: preferences
        )
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections()

        await manager.updateLeaderKey("f18")

        XCTAssertEqual(try storedLeader(defaults), .default)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(blocked).path))
    }

    @MainActor
    func testManagerCommitsAppliedAndPendingLeaderButRestoresRejectedLeader() async throws {
        for disposition: ReloadDisposition in [.applied, .pending, .rejected] {
            let caseDirectory = directory.appendingPathComponent(String(describing: disposition))
            let (manager, _) = try await makeManager(at: caseDirectory)
            try preferencesReset(to: .default)
            manager.ruleCollections = try leaderCollections()
            var reloadCount = 0
            var errors: [String] = []
            manager.onError = { errors.append($0) }
            manager.onRulesChanged = {
                reloadCount += 1
                return ReloadResult(
                    success: disposition == .applied,
                    response: nil,
                    errorMessage: disposition == .rejected ? "rejected" : nil,
                    protocol: nil,
                    disposition: disposition
                )
            }

            await manager.updateLeaderKey("tab")

            let expected = disposition == .rejected
                ? LeaderKeyPreference.default
                : LeaderKeyPreference(key: "tab", targetLayer: .navigation, enabled: true)
            XCTAssertEqual(try storedLeader(defaults), expected, "Unexpected durable leader for \(disposition)")
            XCTAssertEqual(reloadCount, disposition == .rejected ? 2 : 1,
                           "Applied/pending should reload once; rejection should reload the restored revision once")
            XCTAssertEqual(errors.isEmpty, disposition != .rejected)
            XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(caseDirectory).path))
        }
    }

    @MainActor
    func testShortcutListSettingsCommitOnlyWithAcceptedGeneratedConfiguration() async throws {
        let baseline = ShortcutListGenerationInput(
            triggerMode: .holdToShow,
            holdDelayPreset: .long,
            customHoldDelayMs: 200
        )
        let candidate = ShortcutListGenerationInput(
            triggerMode: .tapToToggle,
            holdDelayPreset: .custom,
            customHoldDelayMs: 444
        )

        for disposition: ReloadDisposition in [.applied, .pending, .rejected] {
            let caseDirectory = directory.appendingPathComponent("shortcut-\(disposition)")
            defaults.set(baseline.triggerMode.rawValue, forKey: "KeyPath.ContextHUD.TriggerMode")
            defaults.set(baseline.holdDelayPreset.rawValue, forKey: "KeyPath.ContextHUD.HoldDelayPreset")
            defaults.set(baseline.customHoldDelayMs, forKey: "KeyPath.ContextHUD.HoldDelayCustomMs")
            let (manager, _) = try await makeManager(at: caseDirectory)
            manager.preferencesService.reloadShortcutListGenerationInput(from: defaults)
            manager.ruleCollections = try leaderCollections()
            var reloadCount = 0
            manager.onRulesChanged = {
                reloadCount += 1
                return ReloadResult(
                    success: disposition == .applied,
                    response: nil,
                    errorMessage: disposition == .rejected ? "rejected" : nil,
                    protocol: nil,
                    disposition: disposition
                )
            }

            let success = await manager.applyShortcutListGenerationInput(candidate)
            XCTAssertEqual(success, disposition != .rejected)
            let expected = disposition == .rejected ? baseline : candidate
            XCTAssertEqual(defaults.string(forKey: "KeyPath.ContextHUD.TriggerMode"), expected.triggerMode.rawValue)
            XCTAssertEqual(defaults.string(forKey: "KeyPath.ContextHUD.HoldDelayPreset"), expected.holdDelayPreset.rawValue)
            XCTAssertEqual(defaults.object(forKey: "KeyPath.ContextHUD.HoldDelayCustomMs") as? Int, expected.customHoldDelayMs)
            XCTAssertEqual(manager.preferencesService.shortcutListGenerationInput, expected)
            XCTAssertEqual(reloadCount, disposition == .rejected ? 2 : 1)
        }
    }

    @MainActor
    func testDeviceSelectionsCommitOnlyAfterRestartAndRestoreOnRejection() async throws {
        for restartSucceeds in [true, false] {
            let caseDirectory = directory.appendingPathComponent("device-\(restartSucceeds)")
            let cache = DeviceSelectionCache()
            let deviceStore = DeviceSelectionStore.testStore(
                at: caseDirectory.appendingPathComponent("DeviceSelection.json"), cache: cache
            )
            cache.updateConnectedDevices([
                ConnectedDevice(hash: "a", vendorID: 1, productID: 2, productKey: "Apple Keyboard", isVirtualHID: false)
            ])
            let baseline = DeviceSelection(hash: "a", productKey: "Apple Keyboard", isEnabled: true, lastSeen: .distantPast)
            let candidate = DeviceSelection(hash: "a", productKey: "Apple Keyboard", isEnabled: false, lastSeen: .now)
            try await deviceStore.saveSelections([baseline])
            try FileManager.default.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
            let configURL = caseDirectory.appendingPathComponent("keypath.kbd")
            let beforeConfig = Data("before-device-config".utf8)
            try beforeConfig.write(to: configURL)
            let (manager, _) = try await makeManager(at: caseDirectory, deviceSelectionStore: deviceStore)
            manager.ruleCollections = try leaderCollections()
            var restartCount = 0

            let success = await manager.applyDeviceSelections([candidate]) {
                restartCount += 1
                return restartSucceeds
            }

            XCTAssertEqual(success, restartSucceeds)
            XCTAssertEqual(restartCount, restartSucceeds ? 1 : 2)
            let expected = restartSucceeds ? candidate : baseline
            let persistedSelections = try await deviceStore.loadForMutation()
            let cachedSelections = cache.allSelections()
            XCTAssertEqual(persistedSelections.count, 1)
            XCTAssertEqual(cachedSelections.count, 1)
            XCTAssertEqual(persistedSelections.first?.hash, expected.hash)
            XCTAssertEqual(persistedSelections.first?.productKey, expected.productKey)
            XCTAssertEqual(persistedSelections.first?.isEnabled, expected.isEnabled)
            XCTAssertEqual(cachedSelections.first?.hash, expected.hash)
            XCTAssertEqual(cachedSelections.first?.productKey, expected.productKey)
            XCTAssertEqual(cachedSelections.first?.isEnabled, expected.isEnabled)
            let persistedConfig = try Data(contentsOf: configURL)
            if restartSucceeds {
                XCTAssertNotEqual(persistedConfig, beforeConfig)
                XCTAssertTrue(String(decoding: persistedConfig, as: UTF8.self).contains("macos-dev-names-include"))
            } else {
                XCTAssertEqual(persistedConfig, beforeConfig)
            }
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: RecoverableRuleWrite.journalURL(caseDirectory, scope: .deviceRules).path
            ))
        }
    }

    @MainActor
    func testInterruptedDeviceWriteRestoresConfigSelectionAndRequiresRestart() async throws {
        let caseDirectory = directory.appendingPathComponent("device-crash")
        let cache = DeviceSelectionCache()
        let deviceStore = DeviceSelectionStore.testStore(
            at: caseDirectory.appendingPathComponent("DeviceSelection.json"), cache: cache
        )
        cache.updateConnectedDevices([
            ConnectedDevice(hash: "a", vendorID: 1, productID: 2, productKey: "Apple Keyboard", isVirtualHID: false)
        ])
        let baseline = DeviceSelection(hash: "a", productKey: "Apple Keyboard", isEnabled: true, lastSeen: .distantPast)
        let candidate = DeviceSelection(hash: "a", productKey: "Apple Keyboard", isEnabled: false, lastSeen: .now)
        try await deviceStore.saveSelections([baseline])
        try FileManager.default.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
        let configURL = caseDirectory.appendingPathComponent("keypath.kbd")
        let beforeConfig = Data("before-crash-device-config".utf8)
        try beforeConfig.write(to: configURL)
        let (manager, service) = try await makeManager(at: caseDirectory, deviceSelectionStore: deviceStore)
        manager.ruleCollections = try leaderCollections()

        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(
                ruleCollections: manager.ruleCollections, customRules: manager.customRules,
                collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore,
                mutationPermit: permit, deviceSelections: [candidate]
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: RecoverableRuleWrite.journalURL(caseDirectory, scope: .deviceRules).path
        ))

        _ = try await service.recoverPendingRuleWrite(
            collectionStore: manager.ruleCollectionStore,
            customStore: manager.customRulesStore
        )
        XCTAssertEqual(try Data(contentsOf: configURL), beforeConfig)
        let restored = try await deviceStore.loadForMutation()
        XCTAssertEqual(restored.first?.isEnabled, baseline.isEnabled)
        XCTAssertEqual(cache.allSelections().first?.isEnabled, baseline.isEnabled)
        var restartCount = 0
        let handled = try await service.applyRecoveredDeviceRuntimeRestartIfNeeded {
            restartCount += 1
            return true
        }
        XCTAssertTrue(handled)
        XCTAssertEqual(restartCount, 1)
    }

    @MainActor
    func testManagerRestoresLeaderWhenDurabilityBarrierFails() async throws {
        let barrierCalls = LockedCounter()
        let (manager, _) = try await makeManager(at: directory, synchronizePreferences: { _ in
            barrierCalls.increment()
            return false
        })
        try preferencesReset(to: .default)
        manager.ruleCollections = try leaderCollections()
        var reloadCount = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloadCount += 1
            return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .applied)
        }

        await manager.updateLeaderKey("tab")

        XCTAssertEqual(try storedLeader(defaults), .default)
        XCTAssertEqual(barrierCalls.value, 1)
        XCTAssertEqual(reloadCount, 0)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    @MainActor
    func testRootMutationRefreshesLeaderCommittedByAnotherServiceBeforeRollback() async throws {
        let (manager, _) = try await makeManager(at: directory)
        try preferencesReset(to: .default)
        manager.ruleCollections = try leaderCollections()
        let newer = LeaderKeyPreference(key: "f17", targetLayer: .navigation, enabled: true)
        try defaults.set(JSONEncoder().encode(newer), forKey: PreferencesService.leaderKeyPreferenceKey)
        manager.onRulesChanged = {
            ReloadResult(success: false, response: nil, errorMessage: "rejected", protocol: nil, disposition: .rejected)
        }

        await manager.updateLeaderKey("tab")

        XCTAssertEqual(try storedLeader(defaults), newer)
    }

    @MainActor
    func testManagerRejectsPreferenceChangedAfterSnapshotBeforeJournal() async throws {
        let (manager, _) = try await makeManager(at: directory)
        try preferencesReset(to: .default)
        manager.ruleCollections = try leaderCollections()
        let beforeFiles = ruleFiles(at: directory)
        let intervening = LeaderKeyPreference(key: "f17", targetLayer: .navigation, enabled: true)
        let interveningData = try JSONEncoder().encode(intervening)
        var reloadCount = 0
        manager.onBeforeSave = {
            self.defaults.set(interveningData, forKey: PreferencesService.leaderKeyPreferenceKey)
        }
        manager.onRulesChanged = {
            reloadCount += 1
            return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .applied)
        }

        await manager.updateLeaderKey("tab")

        XCTAssertEqual(reloadCount, 0)
        XCTAssertEqual(try storedLeader(defaults), intervening)
        XCTAssertEqual(ruleFiles(at: directory), beforeFiles)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    @MainActor
    func testBootstrapRecoversInterruptedLeaderAndRuleRevision() async throws {
        let (stagingManager, stagingService) = try await makeManager(at: directory)
        try preferencesReset(to: .default)
        stagingManager.ruleCollections = try leaderCollections()
        let attempted = LeaderKeyPreference(key: "tab", targetLayer: .navigation, enabled: true)
        try await stagingService.operationGate.withOperation { @MainActor permit in
            _ = try await stagingService.stageRuleState(
                ruleCollections: stagingManager.ruleCollections,
                customRules: [],
                collectionStore: stagingManager.ruleCollectionStore,
                customStore: stagingManager.customRulesStore,
                mutationPermit: permit,
                preferenceDefaults: self.defaults,
                preferenceChanges: [.leader(
                    before: defaults.data(forKey: PreferencesService.leaderKeyPreferenceKey),
                    after: JSONEncoder().encode(attempted)
                )],
                leaderKeyPreference: attempted
            )
        }
        XCTAssertEqual(try storedLeader(defaults), attempted)

        let (recoveringManager, _) = try await makeManager(at: directory)
        recoveringManager.onRulesChanged = {
            ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .applied)
        }
        await recoveringManager.bootstrap()

        XCTAssertEqual(try storedLeader(defaults), .default)
        XCTAssertEqual(recoveringManager.preferencesService.leaderKeyPreference, .default)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    private func leaderCollections() throws -> [RuleCollection] {
        try [XCTUnwrap(RuleCollectionCatalog().defaultCollections().first {
            $0.id == RuleCollectionIdentifier.leaderKey
        })]
    }

    private func initialFiles() throws -> [String: URL] {
        let files = [
            "config": directory.appendingPathComponent("keypath.kbd"),
            "collections": directory.appendingPathComponent("RuleCollections.json"),
            "customRules": directory.appendingPathComponent("CustomRules.json"),
        ]
        for (role, url) in files {
            try Data("before-\(role)".utf8).write(to: url)
        }
        return files
    }

    private func stage(
        files: [String: URL], leader: LeaderKeyPreference
    ) throws -> RecoverableRuleWrite.PendingWrite {
        try RecoverableRuleWrite.stage(
            files: files,
            contents: Dictionary(uniqueKeysWithValues: files.map { ($0.key, Data("after-\($0.key)".utf8)) }),
            directory: directory,
            scope: .rules,
            preferences: defaults,
            preferenceChanges: [.leader(
                before: defaults.data(forKey: PreferencesService.leaderKeyPreferenceKey),
                after: JSONEncoder().encode(leader)
            )]
        )
    }

    private func ruleFiles(at directory: URL) -> [String: Data?] {
        Dictionary(uniqueKeysWithValues: ["keypath.kbd", "RuleCollections.json", "CustomRules.json"].map { name in
            let url = directory.appendingPathComponent(name)
            return (name, try? Data(contentsOf: url))
        })
    }

    private func storedLeader(_ defaults: UserDefaults) throws -> LeaderKeyPreference {
        try JSONDecoder().decode(
            LeaderKeyPreference.self,
            from: XCTUnwrap(defaults.data(forKey: PreferencesService.leaderKeyPreferenceKey))
        )
    }

    private func preferencesReset(to value: LeaderKeyPreference) throws {
        try defaults.set(JSONEncoder().encode(value), forKey: PreferencesService.leaderKeyPreferenceKey)
    }

    @MainActor
    private func makeManager(
        at directory: URL,
        deviceSelectionStore: DeviceSelectionStore = .shared,
        synchronizePreferences: @escaping @Sendable (RecoverableRuleWrite.PreferenceDefaults) -> Bool = { $0.value.synchronize() }
    ) async throws -> (RuleCollectionsManager, ConfigurationService) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(
            configDirectory: directory.path,
            ruleCollectionStore: collections,
            customRulesStore: rules,
            deviceSelectionStore: deviceSelectionStore,
            synchronizePreferences: synchronizePreferences
        )
        // Root mutations refresh their persisted source state before snapshotting.
        // RuleCollectionStore merges omitted catalog entries back in, so persist the
        // full catalog with every non-leader collection disabled. That is the same
        // effective source model the fixture uses, without relying on a missing-file
        // fallback that enables unrelated mappings.
        var sourceCollections = RuleCollectionCatalog().defaultCollections()
        for index in sourceCollections.indices where sourceCollections[index].id != RuleCollectionIdentifier.leaderKey {
            sourceCollections[index].isEnabled = false
        }
        try await collections.saveCollections(sourceCollections)
        try await rules.saveRules([])
        let preferences = PreferencesService(leaderDefaults: defaults)
        let manager = RuleCollectionsManager(
            ruleCollectionStore: collections,
            customRulesStore: rules,
            configurationService: service,
            keymapPreferences: defaults,
            preferencesService: preferences
        )
        return (manager, service)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
}
