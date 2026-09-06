import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class SystemPackTransactionTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!
    private var tracker: InstalledPackTracker!
    private let pack = PackRegistry.launcher

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections().map { collection in
            var value = collection
            value.isEnabled = false
            return value
        }
        try await service.saveRuleState(ruleCollections: manager.ruleCollections, customRules: [], collectionStore: collections, customStore: rules)
        tracker = InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json"))
        try await tracker.upsert(InstalledPackRecord(packID: "unrelated", version: "1", installedAt: Date(timeIntervalSince1970: 42)))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: ConfigurationOperationGate.lockFileURL(for: directory))
        manager = nil
        tracker = nil
        directory = nil
        try await super.tearDown()
    }

    private func files() throws -> [Data] {
        try ["keypath.kbd", "RuleCollections.json", "CustomRules.json", "installed-packs.json"].map {
            try Data(contentsOf: directory.appendingPathComponent($0))
        }
    }

    private static func reload(_ disposition: ReloadDisposition) -> ReloadResult {
        ReloadResult(success: disposition == .applied, response: nil, errorMessage: "injected \(disposition)", protocol: nil, disposition: disposition)
    }

    @discardableResult
    private func install(using tracker: InstalledPackTracker? = nil) async throws -> InstalledPackRecord {
        try await PackInstaller.shared.install(pack, managedDefaultPolicy: .useRecommended, manager: manager,
                                               installedPackTracker: tracker ?? self.tracker)
    }

    func testSnapshotIsPresentInJournaledRecordBeforeRuntimeApplication() async throws {
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            let record = await self.tracker.record(for: self.pack.id)
            XCTAssertEqual(record?.managedCollectionSnapshot?.packID, self.pack.id)
            XCTAssertFalse(record?.managedCollectionSnapshot?.entries.isEmpty ?? true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(self.directory, scope: .packRules).path))
            return Self.reload(.applied)
        }
        let record = try await install()
        XCTAssertEqual(reloads, 1)
        let fresh = InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json"))
        let restoredRecord = await fresh.record(for: pack.id)
        XCTAssertEqual(restoredRecord?.packID, record.packID)
        XCTAssertEqual(restoredRecord?.version, record.version)
        XCTAssertEqual(restoredRecord?.quickSettingValues, record.quickSettingValues)
        XCTAssertEqual(restoredRecord?.managedCollectionSnapshot?.entries, record.managedCollectionSnapshot?.entries)
        // Tracker dates use its existing ISO-8601 seconds precision.
        let restoredDate = try XCTUnwrap(restoredRecord?.managedCollectionSnapshot?.snapshotDate)
        let originalDate = try XCTUnwrap(record.managedCollectionSnapshot?.snapshotDate)
        XCTAssertLessThan(abs(restoredDate.timeIntervalSince(originalDate)), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(directory, scope: .packRules).path))
    }

    func testRejectedInstallRestoresAllFilesAndOriginalCollections() async throws {
        let before = try files()
        let collections = manager.ruleCollections
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            if reloads == 2 { XCTAssertEqual(try? self.files(), before) }
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        do { try await install(); XCTFail("Rejected system pack must fail") }
        catch {}
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(manager.ruleCollections, collections)
    }

    func testMetadataFailureDoesNotApplyOrLeaveSnapshotRecord() async throws {
        let before = try files()
        let collections = manager.ruleCollections
        let failing = InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json"), writeFile: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        manager.onRulesChanged = { XCTFail("Failed staging must not reload"); return Self.reload(.applied) }
        do { try await install(using: failing); XCTFail("Metadata write must fail") }
        catch {}
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(manager.ruleCollections, collections)
    }

    func testRejectedRemovalRestoresInstalledSnapshotWithoutDisablingMoreCollections() async throws {
        try await install()
        let before = try files()
        let collections = manager.ruleCollections
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            if reloads == 2 { XCTAssertEqual(try? self.files(), before) }
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        do {
            try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager, installedPackTracker: tracker)
            XCTFail("Rejected removal must fail")
        } catch {}
        XCTAssertEqual(reloads, 2, "A runtime rejection must not trigger a conflict-disable retry")
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(manager.ruleCollections, collections)
        let record = await tracker.record(for: pack.id)
        XCTAssertNotNil(record?.managedCollectionSnapshot)
    }

    func testPendingRemovalCommitsRestorationAndRemovesSnapshotRecord() async throws {
        let before = manager.ruleCollections
        try await install()
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager, installedPackTracker: tracker)
        XCTAssertEqual(reloads, 1)
        for managed in pack.managedDefaults {
            XCTAssertEqual(manager.ruleCollections.first { $0.id == managed.collectionID }, before.first { $0.id == managed.collectionID })
        }
        let record = await tracker.record(for: pack.id)
        XCTAssertNil(record)
    }

    func testInvalidEmbeddedSnapshotBlocksRemovalBeforeAnyWrite() async throws {
        var record = try await install()
        record.managedCollectionSnapshot = PackCollectionSnapshot(packID: pack.id, entries: [
            .init(collectionID: pack.managedDefaults[0].collectionID, wasEnabled: true, configurationJSON: Data("invalid".utf8))
        ])
        try await tracker.upsert(record)
        let before = try files()
        let collections = manager.ruleCollections
        manager.onRulesChanged = { XCTFail("Invalid restore data must not reload"); return Self.reload(.applied) }
        do {
            try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager, installedPackTracker: tracker)
            XCTFail("Invalid saved settings must block removal")
        } catch {}
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(manager.ruleCollections, collections)
    }

    func testLegacySnapshotStillRestoresAnOlderInstallation() async throws {
        let original = manager.ruleCollections
        var record = try await install()
        let saved = try XCTUnwrap(record.managedCollectionSnapshot)
        record.managedCollectionSnapshot = nil
        try await tracker.upsert(record)
        try await withLegacySnapshot(JSONEncoder().encode(saved)) {
            self.manager.onRulesChanged = { Self.reload(.pending) }
            try await PackInstaller.shared.uninstall(packID: self.pack.id, manager: self.manager, installedPackTracker: self.tracker)
            for managed in self.pack.managedDefaults {
                XCTAssertEqual(self.manager.ruleCollections.first { $0.id == managed.collectionID }, original.first { $0.id == managed.collectionID })
            }
            let installed = await self.tracker.record(for: self.pack.id)
            XCTAssertNil(installed)
        }
    }

    func testCorruptLegacySnapshotPreservesInstalledRevision() async throws {
        var record = try await install()
        record.managedCollectionSnapshot = nil
        try await tracker.upsert(record)
        let before = try files()
        let original = manager.ruleCollections
        try await withLegacySnapshot(Data("corrupt legacy snapshot".utf8)) {
            self.manager.onRulesChanged = { XCTFail("Corrupt restore data must not reload"); return Self.reload(.applied) }
            do {
                try await PackInstaller.shared.uninstall(packID: self.pack.id, manager: self.manager, installedPackTracker: self.tracker)
                XCTFail("Unreadable legacy data must block removal")
            } catch {}
            XCTAssertEqual(try self.files(), before)
            XCTAssertEqual(self.manager.ruleCollections, original)
        }
    }

    private func withLegacySnapshot(_ data: Data, operation: () async throws -> Void) async throws {
        let url = PackCollectionSnapshot.snapshotURL(for: pack.id)
        let previous = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        defer {
            if let previous { try? previous.write(to: url, options: .atomic) }
            else { try? FileManager.default.removeItem(at: url) }
        }
        try await operation()
    }

    func testOlderRecordsDecodeWithoutEmbeddedSnapshot() throws {
        let data = Data("{\"packID\":\"old\",\"version\":\"1\",\"installedAt\":0,\"quickSettingValues\":{}}".utf8)
        let record = try JSONDecoder().decode(InstalledPackRecord.self, from: data)
        XCTAssertNil(record.managedCollectionSnapshot)
    }
}
