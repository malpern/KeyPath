import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class ConfigurationRuleWriteTests: KeyPathTestCase {
    private var directory: URL!
    private var collections: RuleCollectionStore!
    private var customRules: CustomRulesStore!
    private var service: ConfigurationService!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        collections = .testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        customRules = .testStore(at: directory.appendingPathComponent("CustomRules.json"))
        service = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: customRules)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        collections = nil
        customRules = nil
        service = nil
        directory = nil
        try await super.tearDown()
    }

    private func collection(_ name: String) -> RuleCollection {
        RuleCollection(name: name, summary: name, category: .custom,
                       mappings: [KeyMapping(input: "a", action: .keystroke(key: "b"))], isEnabled: true)
    }

    func testObserversSeeBothSourceStoresAlreadyCommitted() async throws {
        let expected = collection("Committed")
        let collectionStore = try XCTUnwrap(collections)
        let customStore = try XCTUnwrap(customRules)
        let observed = expectation(description: "committed observer")
        let token = service.observe { _ in
            let storedCollections = await collectionStore.loadCollections()
            let storedRules = await customStore.loadRules()
            XCTAssertTrue(storedCollections.contains { $0.id == expected.id })
            XCTAssertTrue(storedRules.isEmpty)
            observed.fulfill()
        }
        try await service.saveRuleState(ruleCollections: [expected], customRules: [], collectionStore: collections, customStore: customRules)
        await fulfillment(of: [observed], timeout: 2)
        withExtendedLifetime(token) {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testUnreadableSourceStoreLeavesPriorConfigAndOtherStoreUntouched() async throws {
        let original = collection("Original")
        try await service.saveRuleState(ruleCollections: [original], customRules: [], collectionStore: collections, customStore: customRules)
        let configURL = URL(fileURLWithPath: service.configurationPath)
        let collectionURL = await collections.persistenceURL
        let customURL = await customRules.persistenceURL
        let oldConfig = try Data(contentsOf: configURL)
        let oldCollections = try Data(contentsOf: collectionURL)
        try FileManager.default.removeItem(at: customURL)
        try FileManager.default.createDirectory(at: customURL, withIntermediateDirectories: true)
        let count = ObservationCount()
        let token = service.observe { _ in await count.increment() }
        do {
            try await service.saveRuleState(ruleCollections: [collection("Candidate")], customRules: [], collectionStore: collections, customStore: customRules)
            XCTFail("An unreadable preimage must stop the operation")
        } catch {
            XCTAssertEqual(try Data(contentsOf: configURL), oldConfig)
            XCTAssertEqual(try Data(contentsOf: collectionURL), oldCollections)
            let notifications = await count.value
            XCTAssertEqual(notifications, 0)
        }
        withExtendedLifetime(token) {}
    }

    func testStagedRevisionNotifiesOnlyAfterCommit() async throws {
        let count = ObservationCount()
        let token = service.observe { _ in await count.increment() }
        try await service.operationGate.withOperation { @MainActor permit in
            let write = try await self.service.stageRuleState(
                ruleCollections: [self.collection("Staged")], customRules: [],
                collectionStore: self.collections, customStore: self.customRules, mutationPermit: permit
            )
            let stagedCount = await count.value
            XCTAssertEqual(stagedCount, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(self.directory).path))
            try await self.service.settleRuleWrite(write, commit: true, mutationPermit: permit)
            let committedCount = await count.value
            XCTAssertEqual(committedCount, 1)
        }
        withExtendedLifetime(token) {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testStagedRollbackRestoresExactThreeFileRevisionWithoutNotification() async throws {
        try await service.saveRuleState(ruleCollections: [collection("Original")], customRules: [], collectionStore: collections, customStore: customRules)
        let before = try snapshot()
        let count = ObservationCount()
        let token = service.observe { _ in await count.increment() }
        try await service.operationGate.withOperation { @MainActor permit in
            let write = try await self.service.stageRuleState(
                ruleCollections: [self.collection("Candidate")], customRules: [],
                collectionStore: self.collections, customStore: self.customRules, mutationPermit: permit
            )
            try await self.service.settleRuleWrite(write, commit: false, mutationPermit: permit)
        }
        XCTAssertEqual(try snapshot(), before)
        let notifications = await count.value
        XCTAssertEqual(notifications, 0)
        withExtendedLifetime(token) {}
    }

    func testExternalEditAfterStagePreventsCommitAndRollback() async throws {
        try await service.saveRuleState(ruleCollections: [collection("Original")], customRules: [], collectionStore: collections, customStore: customRules)
        try await service.operationGate.withOperation { @MainActor permit in
            let write = try await self.service.stageRuleState(
                ruleCollections: [self.collection("Candidate")], customRules: [],
                collectionStore: self.collections, customStore: self.customRules, mutationPermit: permit
            )
            try "external edit".write(toFile: self.service.configurationPath, atomically: true, encoding: .utf8)
            let externalRevision = try self.snapshot()
            for commit in [true, false] {
                do {
                    try await self.service.settleRuleWrite(write, commit: commit, mutationPermit: permit)
                    XCTFail("External changes must stop settlement")
                } catch {
                    XCTAssertEqual(try self.snapshot(), externalRevision)
                }
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }

    func testInterruptedStageIsRecoveredByFreshService() async throws {
        try await service.saveRuleState(ruleCollections: [collection("Original")], customRules: [], collectionStore: collections, customStore: customRules)
        let before = try snapshot()
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await self.service.stageRuleState(
                ruleCollections: [self.collection("Interrupted")], customRules: [],
                collectionStore: self.collections, customStore: self.customRules, mutationPermit: permit
            )
        }
        let fresh = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: customRules)
        try await fresh.recoverPendingRuleWrite(collectionStore: collections, customStore: customRules)
        XCTAssertEqual(try snapshot(), before)
    }

    private func snapshot() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: ["keypath.kbd", "RuleCollections.json", "CustomRules.json"].map {
            try ($0, Data(contentsOf: directory.appendingPathComponent($0)))
        })
    }

    func testBootstrapRecoversInterruptedWriteBeforeLoadingSourceStores() async throws {
        let original = collection("Original")
        let candidate = collection("Candidate")
        try await service.saveRuleState(ruleCollections: [original], customRules: [], collectionStore: collections, customStore: customRules)
        let files = await [
            "config": URL(fileURLWithPath: service.configurationPath),
            "collections": collections.persistenceURL,
            "customRules": customRules.persistenceURL
        ]
        var entries: [RecoverableRuleWrite.Entry] = []
        for role in files.keys.sorted() {
            let url = files[role]!
            let before = try Data(contentsOf: url)
            let after = role == "collections" ? try await collections.encodedCollections([candidate]) : before
            entries.append(.init(role: role, path: url.path, before: before, after: after))
        }
        let journal = RecoverableRuleWrite.Journal(version: 1, committed: false, entries: entries)
        try JSONEncoder().encode(journal).write(to: RecoverableRuleWrite.journalURL(directory))
        for entry in entries {
            try entry.after.write(to: files[entry.role]!)
        }
        let manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: customRules, configurationService: service)
        await manager.bootstrap()
        XCTAssertTrue(manager.ruleCollections.contains { $0.id == original.id })
        XCTAssertFalse(manager.ruleCollections.contains { $0.id == candidate.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory).path))
    }
}

private actor ObservationCount {
    var value = 0
    func increment() {
        value += 1
    }
}
