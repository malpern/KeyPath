import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class AppKeymapSaveTests: KeyPathTestCase {
    private struct Fixture {
        let directory: URL
        let service: ConfigurationService
        let store: AppKeymapStore
        let coordinator: SaveCoordinator
        let before: [String: Data]
    }

    func testRejectedReloadRestoresAllFilesAndCachedKeymaps() async throws {
        try await withFixture { fixture in
            var reloads = 0
            let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: Self.addOverride) {
                reloads += 1
                return Self.reload(reloads == 1 ? .rejected : .applied)
            }
            XCTAssertFalse(result.success)
            XCTAssertEqual(reloads, 2)
            guard case .restoredPreviousAppKeymapState = result.recoveryResult else {
                return XCTFail("Expected complete app-keymap file recovery")
            }
            try self.assertOriginalFiles(fixture)
            let cached = await fixture.store.loadKeymaps()
            XCTAssertEqual(cached.first?.overrides.count, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(fixture.directory, scope: .appKeymaps).path))
        }
    }

    func testAppliedRevisionCommitsSourceIncludeAndMainWithOneReload() async throws {
        try await withFixture { fixture in
            var reloads = 0
            let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: Self.addOverride) {
                reloads += 1
                return Self.reload(.applied)
            }
            XCTAssertTrue(result.success)
            XCTAssertEqual(reloads, 1)
            let keymaps = try await fixture.store.loadForMutation()
            XCTAssertEqual(keymaps.first?.overrides.count, 2)
            let main = try String(contentsOf: fixture.directory.appendingPathComponent("keypath.kbd"), encoding: .utf8)
            let include = try String(contentsOf: fixture.directory.appendingPathComponent("keypath-apps.kbd"), encoding: .utf8)
            XCTAssertTrue(main.contains("(include keypath-apps.kbd)"))
            XCTAssertTrue(include.contains("kp-c"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(fixture.directory, scope: .appKeymaps).path))
        }
    }

    func testDuplicateKeyRejectionLeavesEveryFileUntouchedAndDoesNotReload() async throws {
        try await withFixture { fixture in
            let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: { keymaps in
                keymaps[0].overrides.append(AppKeyOverride(inputKey: "a", action: .keystroke(key: "z")))
            }) {
                XCTFail("Invalid source must not reach runtime")
                return Self.reload(.applied)
            }
            XCTAssertFalse(result.success)
            try self.assertOriginalFiles(fixture)
        }
    }

    func testInterruptedStageRecoversBeforeTheNextAppEdit() async throws {
        try await withFixture { fixture in
            try await fixture.service.operationGate.withOperation { @MainActor permit in
                _ = try await fixture.service.stageAppKeymapChange(store: fixture.store, mutationPermit: permit, mutate: Self.addOverride)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(fixture.directory, scope: .appKeymaps).path))
            let fresh = ConfigurationService(configDirectory: fixture.directory.path)
            try await fresh.recoverPendingAppKeymapWrite(store: fixture.store)
            try self.assertOriginalFiles(fixture)
        }
    }

    func testInterruptedAppWriteReloadsOriginalBeforeRejectedEditorCallback() async throws {
        try await withFixture { fixture in
            try await self.interruptAppWrite(fixture)
            var reloads = 0
            var applied = 0
            let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: { _ in
                XCTAssertEqual(reloads, 1)
                XCTAssertEqual(applied, 1)
                throw CancellationError()
            }, runtimeDidApply: { applied += 1 }) {
                reloads += 1
                do { try self.assertOriginalFiles(fixture) } catch { XCTFail("\(error)") }
                return Self.reload(.applied)
            }
            XCTAssertFalse(result.success)
            XCTAssertTrue(result.error is CancellationError)
            if case .idle = fixture.coordinator.saveStatus {} else { XCTFail("Cancellation should leave the editor idle") }
            XCTAssertEqual(reloads, 1)
            try self.assertOriginalFiles(fixture)
        }
    }

    func testFailedInterruptedRecoveryRetriesWithAnotherSaveOwnerBeforeMutation() async throws {
        try await withFixture { fixture in
            try await self.interruptAppWrite(fixture)
            let failed = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: { _ in
                XCTFail("Must not edit while recovery is rejected")
            }) { Self.reload(.rejected) }
            XCTAssertFalse(failed.success)
            XCTAssertTrue(failed.error?.localizedDescription.contains("Recovered files could not be applied") == true)
            XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(fixture.directory, scope: .appKeymaps).path))
            var reloads = 0
            let nextOwner = SaveCoordinator(configurationService: fixture.service)
            let result = await nextOwner.saveAppKeymaps(store: fixture.store, mutate: { _ in
                XCTAssertEqual(reloads, 1)
                throw CancellationError()
            }) {
                reloads += 1
                return Self.reload(.pending)
            }
            XCTAssertFalse(result.success)
            XCTAssertTrue(result.error is CancellationError)
            XCTAssertEqual(reloads, 1)
            try self.assertOriginalFiles(fixture)
        }
    }

    func testRawTransformRecoversAppWriteBeforeReadingOriginal() async throws {
        try await withFixture { fixture in
            try await self.interruptAppWrite(fixture)
            var reloads = 0
            let result = await fixture.coordinator.editConfiguration(transform: { content in
                XCTAssertEqual(reloads, 1)
                XCTAssertEqual(Data(content.utf8), fixture.before["keypath.kbd"])
                throw CancellationError()
            }) {
                reloads += 1
                return Self.reload(.applied)
            }
            XCTAssertFalse(result.success)
            XCTAssertTrue(result.error is CancellationError)
            XCTAssertEqual(reloads, 1)
            try self.assertOriginalFiles(fixture)
        }
    }

    func testRawTransformRechecksRecoveryWithoutDuplicateReload() async throws {
        try await withFixture { fixture in
            try await self.interruptAppWrite(fixture)
            var reloads = 0
            let result = await fixture.coordinator.editConfiguration(transform: { content in
                XCTAssertEqual(reloads, 1)
                return content
            }) {
                reloads += 1
                return Self.reload(.applied)
            }
            XCTAssertTrue(result.success)
            XCTAssertEqual(reloads, 2, "One recovery reload and one accepted edit reload")
            try self.assertOriginalFiles(fixture)
        }
    }

    func testGeneratedValidationCannotSkipInterruptedAppRecovery() async throws {
        try await withFixture { fixture in
            try await self.interruptAppWrite(fixture)
            var reloads = 0
            let result = await fixture.coordinator.saveGeneratedConfig(content: "(invalid") {
                reloads += 1
                return Self.reload(.rejected)
            }
            XCTAssertFalse(result.success)
            XCTAssertEqual(reloads, 1)
            XCTAssertTrue(result.error?.localizedDescription.contains("Recovered files could not be applied") == true)
            try self.assertOriginalFiles(fixture)
        }
    }

    func testHeadlessRecoveryRetainsRuntimeRequirementForLaterOwner() async throws {
        try await withFixture { fixture in
            try await self.interruptAppWrite(fixture)
            try await fixture.service.recoverPendingAppKeymapWrite(store: fixture.store)
            let headless = try await fixture.service.operationGate.withOperation { @MainActor permit in
                try await fixture.service.applyRecoveredRuntimeIfNeeded(mutationPermit: permit, reloadHandler: nil)
            }
            XCTAssertNil(headless)
            var reloads = 0
            let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: { _ in
                XCTAssertEqual(reloads, 1)
                throw CancellationError()
            }) {
                reloads += 1
                return Self.reload(.applied)
            }
            XCTAssertFalse(result.success)
            XCTAssertEqual(reloads, 1)
        }
    }

    func testRuleEditorRecoversAppWriteBeforeMissingRuleExit() async throws {
        try await withFixture { fixture in
            try await self.interruptAppWrite(fixture)
            let manager = RuleCollectionsManager(
                ruleCollectionStore: RuleCollectionStore(fileURL: fixture.directory.appendingPathComponent("RuleCollections.json")),
                customRulesStore: CustomRulesStore(fileURL: fixture.directory.appendingPathComponent("CustomRules.json")),
                configurationService: fixture.service
            )
            var reloads = 0
            manager.onRulesChanged = {
                reloads += 1
                do { try self.assertOriginalFiles(fixture) } catch { XCTFail("\(error)") }
                return Self.reload(.applied)
            }
            await manager.toggleCustomRule(id: UUID(), isEnabled: false)
            XCTAssertEqual(reloads, 1)
            try self.assertOriginalFiles(fixture)
        }
    }

    func testCancellationDuringRecoveryStillAppliesOriginalBeforeReturning() async throws {
        try await withFixture { fixture in
            try await self.interruptAppWrite(fixture)
            let started = expectation(description: "Recovery started")
            var resume: CheckedContinuation<Void, Never>?
            var applied = false
            let task = Task { @MainActor in
                await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: { _ in
                    XCTFail("Cancelled editor must not mutate")
                }, runtimeDidApply: { applied = true }) {
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        started.fulfill()
                    }
                    XCTAssertFalse(Task.isCancelled)
                    return Self.reload(.applied)
                }
            }
            await fulfillment(of: [started], timeout: 5)
            task.cancel()
            resume?.resume()
            let result = await task.value
            XCTAssertFalse(result.success)
            XCTAssertTrue(result.error is CancellationError)
            XCTAssertTrue(applied)
            try self.assertOriginalFiles(fixture)
        }
    }

    private func interruptAppWrite(_ fixture: Fixture) async throws {
        try await fixture.service.operationGate.withOperation { @MainActor permit in
            _ = try await fixture.service.stageAppKeymapChange(store: fixture.store, mutationPermit: permit, mutate: Self.addOverride)
        }
    }

    func testExternalEditDuringRejectedReloadStopsRecoveryWithoutOverwritingIt() async throws {
        try await withFixture { fixture in
            let config = fixture.directory.appendingPathComponent("keypath.kbd")
            let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: Self.addOverride) {
                do { try "external edit".write(to: config, atomically: true, encoding: .utf8) }
                catch { XCTFail("Could not simulate external editor: \(error)") }
                return Self.reload(.rejected)
            }
            XCTAssertFalse(result.success)
            guard case .appKeymapRecoveryFailed = result.recoveryResult else {
                return XCTFail("External revision must require recovery attention")
            }
            XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "external edit")
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(fixture.directory, scope: .appKeymaps).path))
        }
    }

    func testManualMainOrIncludeEditsArePreservedWithoutReload() async throws {
        for name in ["keypath.kbd", "keypath-apps.kbd"] {
            try await withFixture { fixture in
                let url = fixture.directory.appendingPathComponent(name)
                let handwritten = Data(";; Generated by KeyPath\n(defsrc a)\n(deflayer base z)\n".utf8)
                try handwritten.write(to: url)
                let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: Self.addOverride) {
                    XCTFail("A configuration the visual editor cannot reproduce must not reach runtime")
                    return Self.reload(.applied)
                }
                XCTAssertFalse(result.success)
                XCTAssertTrue(result.error?.localizedDescription.contains("configuration was preserved") == true)
                for (file, original) in fixture.before {
                    XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent(file)), file == name ? handwritten : original)
                }
                XCTAssertFalse(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(fixture.directory, scope: .appKeymaps).path))
            }
        }
    }

    func testPendingRevisionPersistsWithoutClaimingApplied() async throws {
        try await withFixture { fixture in
            let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: Self.addOverride) { Self.reload(.pending) }
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.reloadResult?.disposition, .pending)
            let keymaps = try await fixture.store.loadForMutation()
            XCTAssertEqual(keymaps.first?.overrides.count, 2)
        }
    }

    func testCancellationDuringReloadRestoresAllFiles() async throws {
        try await withFixture { fixture in
            let started = expectation(description: "reload started")
            var resume: CheckedContinuation<Void, Never>?
            var reloads = 0
            let task = Task { @MainActor in
                await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: Self.addOverride) {
                    reloads += 1
                    if reloads > 1 { XCTAssertFalse(Task.isCancelled, "Recovery TCP must run outside cancellation") }
                    if reloads == 1 {
                        await withCheckedContinuation { continuation in
                            resume = continuation
                            started.fulfill()
                        }
                    }
                    return Self.reload(.applied)
                }
            }
            await fulfillment(of: [started], timeout: 5)
            task.cancel()
            resume?.resume()
            let result = await task.value
            XCTAssertFalse(result.success)
            XCTAssertTrue(result.error is CancellationError)
            XCTAssertEqual(reloads, 2)
            try self.assertOriginalFiles(fixture)
        }
    }

    func testRemovingLastAppMappingCommitsMainWithoutAnInclude() async throws {
        try await withFixture { fixture in
            let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: { $0.removeAll() }) { Self.reload(.applied) }
            XCTAssertTrue(result.success, result.error?.localizedDescription ?? "")
            let keymaps = try await fixture.store.loadForMutation()
            XCTAssertTrue(keymaps.isEmpty)
            XCTAssertFalse(try String(contentsOf: fixture.directory.appendingPathComponent("keypath.kbd"), encoding: .utf8).contains("(include keypath-apps.kbd)"))
        }
    }

    func testManagedCatalogAndCustomRuleConfigurationsRemainEditableAcrossSaves() async throws {
        for selected in [
            RuleCollectionIdentifier.capsLockRemap,
            RuleCollectionIdentifier.capsLockHyperKey,
            RuleCollectionIdentifier.vimNavigation,
            RuleCollectionIdentifier.homeRowMods,
            RuleCollectionIdentifier.homeRowLayerToggles
        ] {
            let collections = RuleCollectionCatalog().defaultCollections().map { original in
                var collection = original
                collection.isEnabled = collection.id == selected
                return collection
            }
            let custom = CustomRule(input: "f24", action: .keystroke(key: "f23"))
            try await withFixture(collections: collections, customRules: [custom]) { fixture in
                for _ in 0 ..< 2 {
                    let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: { keymaps in
                        keymaps[0].overrides[0] = AppKeyOverride(inputKey: "a", action: .keystroke(key: "z"))
                    }) { Self.reload(.applied) }
                    XCTAssertTrue(result.success, "\(selected): \(result.error?.localizedDescription ?? "")")
                }
            }
        }
    }

    func testRuntimeRefreshSeesCommittedSourcesAndRetainsAdmission() async throws {
        try await withFixture { fixture in
            var refreshed = false
            let result = await fixture.coordinator.saveAppKeymaps(store: fixture.store, mutate: Self.addOverride, runtimeDidApply: {
                refreshed = true
                let keymaps = await fixture.store.loadKeymaps()
                XCTAssertEqual(keymaps.first?.overrides.count, 2)
                do {
                    try await fixture.service.operationGate.withOperation { _ in }
                    XCTFail("Runtime refresh must retain admission")
                } catch {
                    if case ConfigurationOperationGate.Failure.recursiveOperation = error {}
                    else { XCTFail("Unexpected error: \(error)") }
                }
            }) { Self.reload(.applied) }
            XCTAssertTrue(result.success)
            XCTAssertTrue(refreshed)
        }
    }

    private static func addOverride(_ keymaps: inout [AppKeymap]) {
        keymaps[0].overrides.append(AppKeyOverride(inputKey: "c", action: .keystroke(key: "d")))
    }

    private static func reload(_ disposition: ReloadDisposition) -> ReloadResult {
        ReloadResult(success: disposition == .applied, response: nil, errorMessage: disposition == .rejected ? "rejected by test engine" : nil, protocol: nil, disposition: disposition)
    }

    private func assertOriginalFiles(_ fixture: Fixture) throws {
        for (name, data) in fixture.before {
            XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent(name)), data, "Must restore \(name)")
        }
    }

    private func withFixture(collections initialCollections: [RuleCollection] = [], customRules initialRules: [CustomRule] = [], _ body: (Fixture) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("app-keymap-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: ConfigurationOperationGate.lockFileURL(for: directory))
        }
        let collections = RuleCollectionStore(fileURL: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore(fileURL: directory.appendingPathComponent("CustomRules.json"))
        let store = AppKeymapStore(fileURL: directory.appendingPathComponent("AppKeymaps.json"))
        try await collections.saveCollections(initialCollections)
        try await rules.saveRules(initialRules)
        try await store.saveKeymaps([AppKeymap(bundleIdentifier: "test.app", displayName: "Test App", overrides: [AppKeyOverride(inputKey: "a", action: .keystroke(key: "b"))])])
        let service = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        let generated = try await service.generateConfiguration(ruleCollections: collections.loadCollections(), customRules: initialRules, appSpecificKeys: ["a"])
        try generated.content.write(to: directory.appendingPathComponent("keypath.kbd"), atomically: true, encoding: .utf8)
        let include = try await AppConfigGenerator.generate(from: store.loadForMutation())
        try include.write(to: directory.appendingPathComponent("keypath-apps.kbd"), atomically: true, encoding: .utf8)
        var before: [String: Data] = [:]
        for name in ["AppKeymaps.json", "keypath.kbd", "keypath-apps.kbd"] {
            before[name] = try Data(contentsOf: directory.appendingPathComponent(name))
        }
        let coordinator = SaveCoordinator(configurationService: service)
        try await body(Fixture(directory: directory, service: service, store: store, coordinator: coordinator, before: before))
    }
}
