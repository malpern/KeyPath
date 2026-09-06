import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class CustomRuleMutationRecoveryTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!

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
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        manager = nil
        directory = nil
        try await super.tearDown()
    }

    private func files() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: ["keypath.kbd", "RuleCollections.json", "CustomRules.json"].map {
            try ($0, Data(contentsOf: directory.appendingPathComponent($0)))
        })
    }

    private static func reload(_ disposition: ReloadDisposition) -> ReloadResult {
        ReloadResult(success: disposition == .applied, response: nil, errorMessage: "injected \(disposition)", protocol: nil, disposition: disposition)
    }

    private func assertRejectedMutationRestores(_ mutate: @MainActor () async -> Void) async throws {
        let before = try files()
        let snapshot = manager.snapshotRuleState()
        var reloads = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloads += 1
            if reloads == 2 {
                do {
                    let restored = try self.files()
                    XCTAssertEqual(restored, before)
                } catch { XCTFail("Could not read restored files: \(error)") }
            }
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        await mutate()
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(manager.ruleCollections, snapshot.collections)
        XCTAssertEqual(manager.customRules, snapshot.customRules)
        XCTAssertEqual(errors.count, 1)
    }

    func testRawEditorRecoveryRefreshesManagerBeforeItsNextMissingRuleExit() async throws {
        let originalRules = manager.customRules
        let before = try files()
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore,
                                                 customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = [] // Interrupted candidate still visible to this editor.
        var reloads = 0
        let result = await SaveCoordinator(configurationService: service).editConfiguration(transform: { _ in
            throw CancellationError()
        }) {
            reloads += 1
            return Self.reload(.applied)
        }
        XCTAssertFalse(result.success)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try files(), before)
        manager.onRulesChanged = { XCTFail("Recovery already applied through the raw editor"); return Self.reload(.applied) }
        await manager.toggleCustomRule(id: UUID(), isEnabled: false)
        XCTAssertEqual(manager.customRules, originalRules)
    }

    func testMapperSaveRefreshesRuleStateRecoveredByRawEditor() async throws {
        let original = manager.customRules[0]
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore,
                                                 customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = []
        let owner = SaveCoordinator(configurationService: service)
        _ = await owner.editConfiguration(transform: { _ in throw CancellationError() }) { Self.reload(.applied) }
        let saved = await owner.saveMapping(input: "f13", output: "f14", ruleCollectionsManager: manager) { Self.reload(.applied) }
        XCTAssertTrue(saved.success)
        XCTAssertTrue(manager.customRules.contains(original))
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertTrue(stored.contains(original))
        XCTAssertTrue(stored.contains { $0.input == "f13" })
    }

    func testMapperRecoversRuntimeBeforeInputValidationCanReject() async throws {
        let service = manager.configurationService
        let before = try files()
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore,
                                                 customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        var reloads = 0
        let result = await SaveCoordinator(configurationService: service).saveMapping(input: "", output: "f14", ruleCollectionsManager: manager) {
            reloads += 1
            XCTAssertEqual(try? self.files(), before)
            return Self.reload(.applied)
        }
        XCTAssertFalse(result.success)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try files(), before)
    }

    func testRejectedSaveRestoresFilesAndReportsFailure() async throws {
        try await assertRejectedMutationRestores {
            let saved = await self.manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")))
            XCTAssertFalse(saved)
        }
    }

    func testRejectedToggleRestoresEnabledState() async throws {
        try await assertRejectedMutationRestores {
            await self.manager.toggleCustomRule(id: self.manager.customRules[0].id, isEnabled: false)
        }
    }

    func testRejectedRemovalRestoresDeletedRule() async throws {
        try await assertRejectedMutationRestores {
            await self.manager.removeCustomRule(id: self.manager.customRules[0].id)
        }
    }

    func testRejectedClearRestoresAllRules() async throws {
        try await assertRejectedMutationRestores { await self.manager.clearAllCustomRules() }
    }

    func testPendingSaveCommitsWithoutRecoveryOrError() async throws {
        var reloads = 0
        manager.onError = { XCTFail("Pending save is not a failure: \($0)") }
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        let saved = await manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")))
        XCTAssertTrue(saved)
        XCTAssertEqual(reloads, 1)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(Set(stored.map(\.input)), ["f13", "f20"])
    }

    func testSkippedReloadCommitsWithoutInventingRuntimeWork() async throws {
        manager.onRulesChanged = { XCTFail("Reload was explicitly skipped"); return Self.reload(.applied) }
        let saved = await manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")), skipReload: true)
        XCTAssertTrue(saved)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(stored.count, 2)
    }

    func testExternalSourceEditIsNotOverwrittenByManagerRollback() async throws {
        var expected: [String: Data]?
        var reloads = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloads += 1
            do {
                try Data("external edit".utf8).write(to: self.directory.appendingPathComponent("CustomRules.json"))
                expected = try self.files()
            } catch { XCTFail("Could not inject external edit: \(error)") }
            return Self.reload(.rejected)
        }
        await manager.removeCustomRule(id: manager.customRules[0].id)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try files(), expected)
        XCTAssertEqual(manager.customRules.count, 1)
        XCTAssertTrue(errors.first?.contains("Recovery needs attention") == true)
    }

    func testEditRecoversInterruptedSourcesBeforePreparingNextRule() async throws {
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = []
        let saved = await manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")))
        XCTAssertTrue(saved)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(Set(stored.map(\.input)), ["f13", "f20"])
    }

    func testUnreadableRecoveredSourcesBlockRetriesUntilRepaired() async throws {
        let service = manager.configurationService
        let sourceURL = directory.appendingPathComponent("RuleCollections.json")
        let originalCollections = try Data(contentsOf: sourceURL)
        try Data("damaged source".utf8).write(to: sourceURL)
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = []
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        let proposed = CustomRule(input: "f13", action: .keystroke(key: "f14"))
        let first = await manager.saveCustomRule(proposed)
        XCTAssertFalse(first)
        let recoveredFiles = try files()
        let retry = await manager.saveCustomRule(proposed)
        XCTAssertFalse(retry)
        XCTAssertEqual(try files(), recoveredFiles)
        XCTAssertEqual(errors.count, 2)
        try originalCollections.write(to: sourceURL)
        let repaired = await manager.saveCustomRule(proposed)
        XCTAssertTrue(repaired)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(Set(stored.map(\.input)), ["f13", "f20"])
    }

    func testPackPickerReadsRecoveredRuleBeforeEditing() async throws {
        manager.customRules[0].packSource = "test-pack"
        let service = manager.configurationService
        try await service.saveRuleState(ruleCollections: [], customRules: manager.customRules,
                                        collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore)
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = []
        let saved = await PackInstaller.shared.updateTapHold(packID: "test-pack", input: "f20", tap: "esc", manager: manager)
        XCTAssertTrue(saved)
        let stored = try await manager.customRulesStore.loadForMutation()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.action.outputString, "esc")
        XCTAssertEqual(stored.first?.packSource, "test-pack")
    }

    func testCancelledSaveRestoresFilesWithoutErrorFeedback() async throws {
        let before = try files()
        let rules = manager.customRules
        var operation: Task<Bool, Never>?
        var reloads = 0
        manager.onError = { XCTFail("Cancellation must remain silent: \($0)") }
        manager.onRulesChanged = {
            reloads += 1
            if reloads == 1 { operation?.cancel() }
            else { XCTAssertFalse(Task.isCancelled, "Recovery must not inherit cancellation") }
            return Self.reload(.applied)
        }
        operation = Task { @MainActor in
            await self.manager.saveCustomRule(CustomRule(input: "f13", action: .keystroke(key: "f14")))
        }
        let saved = await operation!.value
        XCTAssertFalse(saved)
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(manager.customRules, rules)
    }

    func testInterruptedRecoveryReloadsBeforeMissingRuleExit() async throws {
        let before = try files()
        try await stageInterruptedEmptyRules()
        var reloads = 0
        manager.onRulesChanged = {
            reloads += 1
            do {
                let restored = try self.files()
                XCTAssertEqual(restored, before)
            } catch { XCTFail("Cannot read recovery: \(error)") }
            return Self.reload(.applied)
        }
        await manager.toggleCustomRule(id: UUID(), isEnabled: false)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try files(), before)
    }

    func testRejectedInterruptedRecoveryIsRetriedBeforeNextEdit() async throws {
        let before = try files()
        try await stageInterruptedEmptyRules()
        var reloads = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloads += 1
            XCTAssertFalse(Task.isCancelled)
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        await manager.toggleCustomRule(id: UUID(), isEnabled: false)
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(errors.count, 1)
        await manager.toggleCustomRule(id: UUID(), isEnabled: false)
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(try files(), before)
    }

    private func stageInterruptedEmptyRules() async throws {
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.customRules = []
    }

    func testLocalLayerRefreshDoesNotEmitRuntimeHeartbeat() {
        let counter = HeartbeatCounter()
        let token = NotificationCenter.default.addObserver(forName: .kanataTcpHeartbeat, object: nil, queue: nil) { _ in counter.increment() }
        defer { NotificationCenter.default.removeObserver(token) }
        manager.refreshLayerIndicatorState()
        XCTAssertEqual(counter.value, 0)
        manager.updateActiveLayerName("base")
        XCTAssertEqual(counter.value, 1, "Even an unchanged observed layer is real heartbeat evidence")
    }
}

private final class HeartbeatCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
}
