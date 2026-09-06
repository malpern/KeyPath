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
            let (manager, _) = try makeManager(at: caseDirectory)
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
    func testManagerRestoresLeaderWhenDurabilityBarrierFails() async throws {
        let barrierCalls = LockedCounter()
        let (manager, _) = try makeManager(at: directory, synchronizePreferences: { _ in
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
        let (manager, _) = try makeManager(at: directory)
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
        let (manager, _) = try makeManager(at: directory)
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
        let (stagingManager, stagingService) = try makeManager(at: directory)
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

        let (recoveringManager, _) = try makeManager(at: directory)
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
        synchronizePreferences: @escaping @Sendable (RecoverableRuleWrite.PreferenceDefaults) -> Bool = { $0.value.synchronize() }
    ) throws -> (RuleCollectionsManager, ConfigurationService) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(
            configDirectory: directory.path,
            ruleCollectionStore: collections,
            customRulesStore: rules,
            synchronizePreferences: synchronizePreferences
        )
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
