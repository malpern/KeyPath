import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class PackRuleTransactionTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!
    private var tracker: InstalledPackTracker!
    private var pack: Pack!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.ruleCollections = []
        manager.customRules = [CustomRule(input: "f20", action: .keystroke(key: "f19"))]
        try await service.saveRuleState(ruleCollections: [], customRules: manager.customRules, collectionStore: collections, customStore: rules)
        tracker = InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json"))
        try await tracker.upsert(InstalledPackRecord(packID: "unrelated", version: "1", installedAt: Date(timeIntervalSince1970: 42)))
        pack = makePack(inputs: ["f13", "f15"])
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        manager = nil
        tracker = nil
        pack = nil
        directory = nil
        try await super.tearDown()
    }

    private func makePack(inputs: [String]) -> Pack {
        Pack(id: "com.keypath.test.batch", version: "1", name: "Batch", tagline: "Batch",
             shortDescription: "Batch", longDescription: "", category: "Test", iconSymbol: "testtube.2",
             bindings: inputs.map { PackBindingTemplate(input: $0, output: "f14", title: $0) })
    }

    private func snapshot() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: ["keypath.kbd", "RuleCollections.json", "CustomRules.json", "installed-packs.json"].map {
            try ($0, Data(contentsOf: directory.appendingPathComponent($0)))
        })
    }

    private static func reload(_ disposition: ReloadDisposition) -> ReloadResult {
        ReloadResult(success: disposition == .applied, response: nil,
                     errorMessage: disposition == .applied ? nil : "injected \(disposition)", protocol: nil, disposition: disposition)
    }

    func testBatchPublishesOnceAfterAllRulesAndRecordCommitWithOneReload() async throws {
        let count = PackCommitCount()
        let token = manager.configurationService.observe { _ in await count.increment() }
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            let staged = try? await self.manager.customRulesStore.loadForMutation()
            XCTAssertEqual(staged?.count, 3)
            let record = await self.tracker.record(for: self.pack.id)
            XCTAssertNotNil(record)
            let notifications = await count.value
            XCTAssertEqual(notifications, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(self.directory, scope: .packRules).path))
            return Self.reload(.applied)
        }
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
        XCTAssertEqual(reloads, 1)
        let notifications = await count.value
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(manager.customRules.count, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory, scope: .packRules).path))
        withExtendedLifetime(token) {}
    }

    func testRejectedReloadRestoresFourFilesBeforeRecoveryAndManagerOnFailure() async throws {
        let before = try snapshot()
        let oldRules = manager.customRules
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            if reloads > 1 {
                do {
                    let restored = try self.snapshot()
                    XCTAssertEqual(restored, before)
                } catch { XCTFail("Missing restored revision: \(error)") }
            }
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        do {
            _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
            XCTFail("Rejected installation must fail")
        } catch {}
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.customRules, oldRules)
    }

    func testConflictingLaterBindingLeavesNoPartialInstall() async throws {
        manager.customRules[0].packSource = pack.id
        try await manager.configurationService.saveRuleState(ruleCollections: [], customRules: manager.customRules,
                                                             collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore)
        let before = try snapshot()
        let oldRules = manager.customRules
        pack = makePack(inputs: ["f13", "f20"])
        manager.onConflictResolution = { _ in .keepExisting }
        manager.onRulesChanged = { XCTFail("A declined batch must not reload"); return Self.reload(.applied) }
        do {
            _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
            XCTFail("Conflict should cancel preparation")
        } catch {}
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.customRules, oldRules)
    }

    func testSkippedReloadCommitsTheWholeBatchWithoutCallingRuntime() async throws {
        manager.onRulesChanged = { XCTFail("Explicit skip must remain a skip"); return Self.reload(.applied) }
        _ = try await PackInstaller.shared.install(pack, manager: manager, skipFinalReload: true, installedPackTracker: tracker)
        let record = await tracker.record(for: pack.id)
        XCTAssertNotNil(record)
        XCTAssertEqual(manager.customRules.count, 3)
    }

    func testPendingReloadCommitsWithoutRecoveryOrSecondReload() async throws {
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
        XCTAssertEqual(reloads, 1)
        let record = await tracker.record(for: pack.id)
        XCTAssertNotNil(record)
        XCTAssertEqual(manager.customRules.count, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory, scope: .packRules).path))
    }

    func testCancellationRestoresFourFilesAndUsesUncancelledRecovery() async throws {
        let before = try snapshot()
        let oldRules = manager.customRules
        var operation: Task<InstalledPackRecord, Error>?
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            if reloads == 1 { operation?.cancel() }
            else { XCTAssertFalse(Task.isCancelled) }
            return Self.reload(.applied)
        }
        operation = Task { @MainActor in
            try await PackInstaller.shared.install(self.pack, manager: self.manager, installedPackTracker: self.tracker)
        }
        do {
            _ = try await operation!.value
            XCTFail("Cancelled application must recover")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.customRules, oldRules)
    }

    func testInterruptedPackStageRecoversThroughStandardStartupRuleRecovery() async throws {
        let before = try snapshot()
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(
                ruleCollections: [], customRules: [], collectionStore: self.manager.ruleCollectionStore,
                customStore: self.manager.customRulesStore, mutationPermit: permit,
                packRecord: .init(tracker: self.tracker, record: InstalledPackRecord(packID: self.pack.id, version: "2"))
            )
        }
        let fresh = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: manager.ruleCollectionStore, customRulesStore: manager.customRulesStore)
        try await fresh.recoverPendingRuleWrite(collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore)
        XCTAssertEqual(try snapshot(), before)
    }

    func testMetadataOnlyToggleRecoversInterruptedPackBeforeChangingRecords() async throws {
        let before = try snapshot()
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(
                ruleCollections: [], customRules: [], collectionStore: self.manager.ruleCollectionStore,
                customStore: self.manager.customRulesStore, mutationPermit: permit,
                packRecord: .init(tracker: self.tracker, record: InstalledPackRecord(packID: self.pack.id, version: "2"))
            )
        }
        _ = try await PackInstaller.shared.setVisualPackEnabled(PackRegistry.keystrokeHistory, enabled: true,
                                                                manager: manager, installedPackTracker: tracker)
        let after = try snapshot()
        for name in ["keypath.kbd", "RuleCollections.json", "CustomRules.json"] {
            XCTAssertEqual(after[name], before[name])
        }
        let interruptedRecord = await tracker.record(for: pack.id)
        let visualRecord = await tracker.record(for: PackRegistry.keystrokeHistory.id)
        let originalRecord = await tracker.record(for: "unrelated")
        XCTAssertNil(interruptedRecord)
        XCTAssertNotNil(visualRecord)
        XCTAssertNotNil(originalRecord)
    }

    func testNextInstallUsesRecoveredSourcesInsteadOfInterruptedManagerState() async throws {
        let priorRules = manager.customRules
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(
                ruleCollections: [], customRules: [], collectionStore: self.manager.ruleCollectionStore,
                customStore: self.manager.customRulesStore, mutationPermit: permit,
                packRecord: .init(tracker: self.tracker, record: InstalledPackRecord(packID: "interrupted", version: "2"))
            )
        }
        manager.customRules = []
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
        XCTAssertTrue(manager.customRules.contains(where: { $0.id == priorRules[0].id }))
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(stored.count, priorRules.count + pack.bindings.count)
        let interrupted = await tracker.record(for: "interrupted")
        XCTAssertNil(interrupted)
    }

    func testExternalMetadataEditStopsRecoveryWithoutOverwritingAnyFile() async throws {
        var externalRevision: [String: Data]?
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            do {
                try Data("external metadata edit".utf8).write(to: self.directory.appendingPathComponent("installed-packs.json"))
                externalRevision = try self.snapshot()
            } catch { XCTFail("External edit failed: \(error)") }
            return Self.reload(.rejected)
        }
        do {
            _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
            XCTFail("Recovery conflict must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Recovery needs attention")) }
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try snapshot(), externalRevision)
        XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory, scope: .packRules).path))
    }
}

private actor PackCommitCount {
    var value = 0
    func increment() {
        value += 1
    }
}
