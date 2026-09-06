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
        manager.customRules = [CustomRule(input: "f20", action: .keystroke(key: "f19"), createdAt: Date(timeIntervalSince1970: 42))]
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

    func testMissingCollectionResultExplainsFailureWithoutClaimingCancellation() async throws {
        let before = try snapshot()
        let result = await manager.toggleCollectionResult(id: UUID(), isEnabled: true)
        XCTAssertFalse(result.success)
        XCTAssertFalse(result.error is CancellationError)
        XCTAssertTrue(result.error?.localizedDescription.contains("No matching collection") == true)
        XCTAssertEqual(try snapshot(), before)
    }

    func testDeclinedCollectionConflictPreservesExistingRuleAndExplainsFailure() async throws {
        pack = PackRegistry.capsLockToEscape
        manager.customRules.append(CustomRule(input: "caps", action: .keystroke(key: "f13")))
        let before = try snapshot()
        let originalRules = manager.customRules
        manager.onConflictResolution = { _ in .keepExisting }
        manager.onRulesChanged = { XCTFail("Declined conflict must not reload"); return Self.reload(.applied) }
        do {
            _ = try await PackInstaller.shared.install(pack, autoResolveCollectionConflicts: false, manager: manager, installedPackTracker: tracker)
            XCTFail("Declined installation must fail")
        } catch {
            XCTAssertFalse(error is CancellationError)
            XCTAssertTrue(error.localizedDescription.contains("existing mapping was kept"))
        }
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.customRules, originalRules)
    }

    func testCollectionPackStagesRecordWithCollectionBeforeOneAcceptedReload() async throws {
        pack = PackRegistry.capsLockToEscape
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            let record = await self.tracker.record(for: self.pack.id)
            XCTAssertNotNil(record)
            XCTAssertTrue(self.manager.ruleCollections.contains { $0.id == self.pack.associatedCollectionID && $0.isEnabled })
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(self.directory, scope: .packRules).path))
            return Self.reload(.applied)
        }
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
        XCTAssertEqual(reloads, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory, scope: .packRules).path))
    }

    func testCollectionPackMetadataWriteFailureLeavesNoPartialActivation() async throws {
        pack = PackRegistry.capsLockToEscape
        let before = try snapshot()
        let collections = manager.ruleCollections
        let failing = InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json"), writeFile: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        manager.onRulesChanged = { XCTFail("Failed staging must not reload"); return Self.reload(.applied) }
        do {
            _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: failing)
            XCTFail("Metadata staging failure must fail installation")
        } catch let error as PackInstaller.InstallError {
            guard case let .saveFailed(reason) = error else { return XCTFail("Wrong failure: \(error)") }
            XCTAssertTrue(reason.contains(CocoaError(.fileWriteNoPermission).localizedDescription))
            XCTAssertTrue(reason.contains("prior files were restored"))
        }
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.ruleCollections, collections)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory, scope: .packRules).path))
    }

    func testRejectedCollectionPackInstallRestoresFourFiles() async throws {
        pack = PackRegistry.capsLockToEscape
        let before = try snapshot()
        let collections = manager.ruleCollections
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            if reloads == 2 { XCTAssertEqual(try? self.snapshot(), before) }
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        do {
            _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
            XCTFail("Rejected collection installation must fail")
        } catch {}
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.ruleCollections, collections)
    }

    func testRejectedCollectionPackUninstallRestoresRecordAndCollection() async throws {
        pack = PackRegistry.capsLockToEscape
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
        let before = try snapshot()
        let collections = manager.ruleCollections
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            let record = await self.tracker.record(for: self.pack.id)
            if reloads == 1 { XCTAssertNil(record) }
            else { XCTAssertNotNil(record); XCTAssertEqual(try? self.snapshot(), before) }
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        do {
            try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager, installedPackTracker: tracker)
            XCTFail("Rejected removal must fail")
        } catch {}
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.ruleCollections, collections)
    }

    func testCollectionPackUninstallPendingCommitsRecordRemovalWithOneReload() async throws {
        pack = PackRegistry.capsLockToEscape
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager, installedPackTracker: tracker)
        XCTAssertEqual(reloads, 1)
        let record = await tracker.record(for: pack.id)
        XCTAssertNil(record)
        XCTAssertFalse(manager.ruleCollections.first { $0.id == pack.associatedCollectionID }?.isEnabled ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory, scope: .packRules).path))
    }

    func testCollectionPackExternalMetadataEditPreservesConflictingRevision() async throws {
        pack = PackRegistry.capsLockToEscape
        var external: [String: Data]?
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            do {
                try Data("external metadata".utf8).write(to: self.directory.appendingPathComponent("installed-packs.json"))
                external = try self.snapshot()
            } catch { XCTFail("\(error)") }
            return Self.reload(.rejected)
        }
        do {
            _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
            XCTFail("External conflict must fail")
        } catch {}
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try snapshot(), external)
        XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory, scope: .packRules).path))
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

    func testUninstallCommitsAllRemovalsWithOneReload() async throws {
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            return Self.reload(.applied)
        }
        try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager, installedPackTracker: tracker)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(manager.customRules.map(\.input), ["f20"])
        let record = await tracker.record(for: pack.id)
        XCTAssertNil(record)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(stored, manager.customRules)
    }

    func testRejectedUninstallRestoresRulesAndInstalledRecord() async throws {
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
        let before = try snapshot()
        let rules = manager.customRules
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        do {
            try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager, installedPackTracker: tracker)
            XCTFail("Rejected removal must fail")
        } catch {}
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.customRules, rules)
    }

    func testUninstallMetadataWriteFailureRestoresExactRevisionWithoutReload() async throws {
        _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
        let before = try snapshot()
        let rules = manager.customRules
        let failingTracker = InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json")) { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        manager.onRulesChanged = { XCTFail("Failed stage must not reload"); return Self.reload(.applied) }
        do {
            try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager, installedPackTracker: failingTracker)
            XCTFail("Metadata failure must fail removal")
        } catch {}
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.customRules, rules)
    }

    private func prepareHomeRowSettings() async throws {
        var collection = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first { $0.id == RuleCollectionIdentifier.homeRowMods })
        collection.isEnabled = true
        manager.ruleCollections = [collection]
        try await manager.configurationService.saveRuleState(ruleCollections: manager.ruleCollections,
                                                             customRules: manager.customRules, collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore)
        try await tracker.upsert(InstalledPackRecord(packID: PackRegistry.homeRowMods.id, version: "1", quickSettingValues: ["holdTimeout": 180]))
    }

    func testPendingTimingChangeCommitsSettingAndCollectionWithOneReload() async throws {
        try await prepareHomeRowSettings()
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        try await PackInstaller.shared.updateQuickSettings(packID: PackRegistry.homeRowMods.id, newValues: ["holdTimeout": 280], manager: manager, installedPackTracker: tracker)
        XCTAssertEqual(reloads, 1)
        let record = await tracker.record(for: PackRegistry.homeRowMods.id)
        XCTAssertEqual(record?.quickSettingValues["holdTimeout"], 280)
        guard case let .homeRowMods(config) = manager.ruleCollections[0].configuration else { return XCTFail("Missing timing configuration") }
        XCTAssertEqual(config.timing.holdDelay, 280)
        let stored = await manager.ruleCollectionStore.loadCollections()
        XCTAssertEqual(stored.first(where: { $0.id == RuleCollectionIdentifier.homeRowMods }), manager.ruleCollections[0])
    }

    func testMissingTimingCollectionDoesNotWriteMetadata() async throws {
        try await prepareHomeRowSettings()
        manager.ruleCollections = []
        try await assertInvalidTimingTargetDoesNotWrite()
    }

    func testMalformedTimingCollectionDoesNotWriteMetadata() async throws {
        try await prepareHomeRowSettings()
        manager.ruleCollections[0].configuration = .list
        try await assertInvalidTimingTargetDoesNotWrite()
    }

    private func assertInvalidTimingTargetDoesNotWrite() async throws {
        let before = try snapshot()
        let collections = manager.ruleCollections
        manager.onRulesChanged = { XCTFail("Invalid target must not reload"); return Self.reload(.applied) }
        do {
            try await PackInstaller.shared.updateQuickSettings(packID: PackRegistry.homeRowMods.id, newValues: ["holdTimeout": 280], manager: manager, installedPackTracker: tracker)
            XCTFail("Invalid timing target must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timing collection")) }
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.ruleCollections, collections)
    }

    func testRejectedTimingChangeRestoresCollectionAndSetting() async throws {
        try await prepareHomeRowSettings()
        let before = try snapshot()
        let collections = manager.ruleCollections
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(reloads == 1 ? .rejected : .applied) }
        do {
            try await PackInstaller.shared.updateQuickSettings(packID: PackRegistry.homeRowMods.id, newValues: ["holdTimeout": 280], manager: manager, installedPackTracker: tracker)
            XCTFail("Rejected timing must fail")
        } catch {}
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.ruleCollections, collections)
    }

    func testInstallRefusesRejectedInterruptedRuntimeRecovery() async throws {
        let before = try snapshot()
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore,
                                                 mutationPermit: permit, packRecord: .init(tracker: self.tracker, record: InstalledPackRecord(packID: "interrupted", version: "2")))
        }
        manager.customRules = []
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.rejected) }
        do {
            _ = try await PackInstaller.shared.install(pack, manager: manager, installedPackTracker: tracker)
            XCTFail("Install must wait for successful recovery")
        } catch let PackInstaller.InstallError.saveFailed(reason) {
            XCTAssertTrue(reason.contains("Recovered files could not be applied"))
        }
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try snapshot(), before)
        XCTAssertEqual(manager.customRules.map(\.input), ["f20"])
        let record = await tracker.record(for: pack.id)
        XCTAssertNil(record)
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
