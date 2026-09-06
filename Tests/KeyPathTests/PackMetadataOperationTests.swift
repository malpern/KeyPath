import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class PackMetadataOperationTests: KeyPathTestCase {
    private struct Fixture {
        let directory: URL
        let manager: RuleCollectionsManager
        let tracker: InstalledPackTracker
    }

    func testVisualToggleUsesTrustedAdmissionWithoutChangingConfiguration() async throws {
        try await withFixture { fixture in
            let pack = PackRegistry.kindaVim
            try await fixture.manager.configurationService.operationGate.withOperation { permit in
                let record = try await PackInstaller.shared.setVisualPackEnabled(
                    pack, enabled: true, quickSettingValues: ["retained": 42], manager: fixture.manager,
                    installedPackTracker: fixture.tracker, mutationPermit: permit
                )
                XCTAssertEqual(record?.quickSettingValues, ["retained": 42])
            }
            let repeated = try await PackInstaller.shared.setVisualPackEnabled(pack, enabled: true, manager: fixture.manager, installedPackTracker: fixture.tracker)
            XCTAssertEqual(repeated?.quickSettingValues, ["retained": 42])
            try await PackInstaller.shared.setVisualPackEnabled(pack, enabled: false, manager: fixture.manager, installedPackTracker: fixture.tracker)
            let installed = await fixture.tracker.isInstalled(packID: pack.id)
            XCTAssertFalse(installed)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("keypath.kbd").path))
        }
    }

    func testMetadataToggleRejectsNonvisualPacks() async throws {
        try await withFixture { fixture in
            let pack = try XCTUnwrap(PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape"))
            do {
                try await PackInstaller.shared.setVisualPackEnabled(pack, enabled: true, manager: fixture.manager, installedPackTracker: fixture.tracker)
                XCTFail("Nonvisual packs require full installation")
            } catch {}
            let records = await fixture.tracker.allInstalled()
            XCTAssertTrue(records.isEmpty)
        }
    }

    func testCatalogInstallStillEnforcesConflicts() async throws {
        try await withFixture { fixture in
            try await fixture.tracker.upsert(InstalledPackRecord(packID: "com.keypath.pack.vim-navigation", version: "1"))
            do {
                try await PackInstaller.shared.install(PackRegistry.kindaVim, manager: fixture.manager, installedPackTracker: fixture.tracker)
                XCTFail("Catalog installation must retain its conflict gate")
            } catch PackInstaller.InstallError.mutuallyExclusive {} catch { XCTFail("Unexpected error: \(error)") }
            // The existing Rules toggle policy is intentionally unchanged in this internal slice.
            try await PackInstaller.shared.setVisualPackEnabled(PackRegistry.kindaVim, enabled: true, manager: fixture.manager, installedPackTracker: fixture.tracker)
        }
    }

    func testBackfillUsesPersistedStateRatherThanStaleManagerState() async throws {
        try await withFixture { fixture in
            let pack = try XCTUnwrap(PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape"))
            var collections = RuleCollectionCatalog().defaultCollections()
            let index = try XCTUnwrap(collections.firstIndex { $0.id == pack.associatedCollectionID })
            collections[index].isEnabled = true
            fixture.manager.ruleCollections = collections
            collections[index].isEnabled = false
            try await fixture.manager.ruleCollectionStore.saveCollections(collections)
            let absent = try await PackInstaller.shared.reconcileInstallRecord(for: pack, manager: fixture.manager, installedPackTracker: fixture.tracker)
            XCTAssertNil(absent)
            collections[index].isEnabled = true
            try await fixture.manager.ruleCollectionStore.saveCollections(collections)
            let restored = try await PackInstaller.shared.reconcileInstallRecord(for: pack, manager: fixture.manager, installedPackTracker: fixture.tracker)
            XCTAssertEqual(restored?.packID, pack.id)
        }
    }

    func testBackfillRecoversInterruptedRuleWriteBeforeReadingSources() async throws {
        try await withFixture { fixture in
            let pack = try XCTUnwrap(PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape"))
            var collections = RuleCollectionCatalog().defaultCollections()
            let index = try XCTUnwrap(collections.firstIndex { $0.id == pack.associatedCollectionID })
            collections[index].isEnabled = false
            try await fixture.manager.ruleCollectionStore.saveCollections(collections)
            let sourceURL = fixture.directory.appendingPathComponent("RuleCollections.json")
            let original = try Data(contentsOf: sourceURL)
            collections[index].isEnabled = true
            let proposed = try await fixture.manager.ruleCollectionStore.encodedCollections(collections)
            _ = try RecoverableRuleWrite.stage(files: [
                "config": fixture.directory.appendingPathComponent("keypath.kbd"),
                "collections": sourceURL,
                "customRules": fixture.directory.appendingPathComponent("CustomRules.json")
            ], contents: ["config": Data("(defsrc)\n(deflayer base)".utf8), "collections": proposed, "customRules": Data("[]".utf8)],
            directory: fixture.directory, scope: .rules)
            var recoveryReloads = 0
            fixture.manager.onRulesChanged = {
                recoveryReloads += 1
                do {
                    let restored = try Data(contentsOf: sourceURL)
                    XCTAssertEqual(restored, original)
                } catch { XCTFail("Could not read restored source: \(error)") }
                return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil, disposition: .applied)
            }
            let record = try await PackInstaller.shared.reconcileInstallRecord(for: pack, manager: fixture.manager, installedPackTracker: fixture.tracker)
            XCTAssertNil(record)
            XCTAssertEqual(recoveryReloads, 1)
            XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        }
    }

    func testDeferredRepairWaitsForTheNotificationOwner() async throws {
        try await withFixture { fixture in
            let pack = try XCTUnwrap(PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape"))
            let started = expectation(description: "notification refresh started")
            var refresh: Task<InstalledPackRecord?, Error>?
            try await fixture.manager.configurationService.operationGate.withOperation { @MainActor _ in
                var collections = RuleCollectionCatalog().defaultCollections()
                let index = try XCTUnwrap(collections.firstIndex { $0.id == pack.associatedCollectionID })
                collections[index].isEnabled = true
                try await fixture.manager.ruleCollectionStore.saveCollections(collections)
                refresh = Task.detached { try await Self.deferredRepair(pack, fixture: fixture, started: started) }
                await fulfillment(of: [started], timeout: 5)
                let installed = await fixture.tracker.isInstalled(packID: pack.id)
                XCTAssertFalse(installed, "Repair must wait for the active writer to release admission")
            }
            let record = try await refresh?.value
            XCTAssertEqual(record?.packID, pack.id)
        }
    }

    func testFailedBackfillDoesNotReportInstalled() async throws {
        try await withFixture { fixture in
            let pack = try XCTUnwrap(PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape"))
            var collections = RuleCollectionCatalog().defaultCollections()
            let index = try XCTUnwrap(collections.firstIndex { $0.id == pack.associatedCollectionID })
            collections[index].isEnabled = true
            try await fixture.manager.ruleCollectionStore.saveCollections(collections)
            let tracker = InstalledPackTracker(fileURL: fixture.directory.appendingPathComponent("failed.json")) { _, _ in
                throw NSError(domain: "write", code: 1)
            }
            do {
                _ = try await PackInstaller.shared.reconcileInstallRecord(for: pack, manager: fixture.manager, installedPackTracker: tracker)
                XCTFail("A failed record write must throw")
            } catch {}
            let installed = await tracker.isInstalled(packID: pack.id)
            XCTAssertFalse(installed)
        }
    }

    func testCorruptMetadataIsPreserved() async throws {
        try await withFixture { fixture in
            let file = fixture.directory.appendingPathComponent("installed-packs.json")
            let corrupt = Data("not json".utf8)
            try corrupt.write(to: file)
            do {
                try await PackInstaller.shared.setVisualPackEnabled(PackRegistry.kindaVim, enabled: true, manager: fixture.manager, installedPackTracker: fixture.tracker)
                XCTFail("Corrupt metadata must prevent mutation")
            } catch {}
            XCTAssertEqual(try Data(contentsOf: file), corrupt)
        }
    }

    private static func deferredRepair(_ pack: Pack, fixture: Fixture, started: XCTestExpectation) async throws -> InstalledPackRecord? {
        started.fulfill()
        return try await PackInstaller.shared.reconcileInstallRecord(for: pack, manager: fixture.manager, installedPackTracker: fixture.tracker)
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pack-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: ConfigurationOperationGate.lockFileURL(for: directory))
        }
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        let manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.onRulesChanged = { XCTFail("Metadata-only work must not reload the engine"); return ReloadResult(
            success: false,
            response: nil,
            errorMessage: "Unexpected reload",
            protocol: nil,
            disposition: .failed
        ) }
        let tracker = InstalledPackTracker(fileURL: directory.appendingPathComponent("installed-packs.json"))
        try await body(Fixture(directory: directory, manager: manager, tracker: tracker))
    }
}
