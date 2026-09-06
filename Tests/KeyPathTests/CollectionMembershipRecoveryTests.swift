import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class CollectionMembershipRecoveryTests: KeyPathTestCase {
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
        manager.ruleCollections = [collection("Existing", layer: .custom("work"))]
        manager.customRules = [CustomRule(input: "f20", action: .keystroke(key: "f19"), createdAt: Date(timeIntervalSince1970: 42), targetLayer: .custom("work"))]
        try await persistFixture()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        manager = nil
        directory = nil
        try await super.tearDown()
    }

    private func collection(_ name: String, layer: RuleCollectionLayer = .base, enabled: Bool = true) -> RuleCollection {
        RuleCollection(id: UUID(), name: name, summary: "", category: .custom,
                       mappings: [KeyMapping(input: "f13", action: .keystroke(key: "f14"), description: "")],
                       isEnabled: enabled, targetLayer: layer)
    }

    private func persistFixture() async throws {
        try await manager.configurationService.saveRuleState(ruleCollections: manager.ruleCollections, customRules: manager.customRules,
                                                             collectionStore: manager.ruleCollectionStore, customStore: manager.customRulesStore)
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

    func testRejectedAdditionRestoresCollections() async throws {
        try await assertRejectedMutationRestores {
            let saved = await self.manager.addCollection(self.collection("New"))
            XCTAssertFalse(saved)
        }
    }

    func testCoordinatorReturnsRejectionAndPublishesRestoredMappings() async throws {
        let coordinator = RuleCollectionsCoordinator(ruleCollectionsManager: manager)
        var observedMappings: [KeyMapping]?
        var notifications = 0
        coordinator.configure(applyMappings: { observedMappings = $0 }, notifyStateChanged: { notifications += 1 })
        let originalMappings = manager.enabledMappings()
        try await assertRejectedMutationRestores {
            let saved = await coordinator.addRuleCollection(self.collection("New"))
            XCTAssertFalse(saved)
        }
        XCTAssertEqual(observedMappings, originalMappings)
        XCTAssertEqual(notifications, 1)
    }

    func testMapperDoesNotSelectRejectedNewLayer() async {
        let runtime = RuntimeCoordinator(injectedConfigurationService: manager.configurationService,
                                         injectedRuleCollectionsManager: manager)
        let viewModel = MapperViewModel()
        viewModel.kanataManager = runtime
        let previousLayer = viewModel.currentLayer
        let failure = expectation(description: "Layer creation rejected")
        var reloads = 0
        manager.onError = { _ in failure.fulfill() }
        manager.onRulesChanged = {
            reloads += 1
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        viewModel.createLayer("Research")
        XCTAssertEqual(viewModel.currentLayer, previousLayer, "Do not select before save settles")
        await fulfillment(of: [failure], timeout: 2)
        XCTAssertEqual(viewModel.currentLayer, previousLayer)
        XCTAssertFalse(manager.ruleCollections.contains { $0.targetLayer == .custom("research") })
    }

    func testRejectedRemovalRestoresCollection() async throws {
        try await assertRejectedMutationRestores {
            await self.manager.removeCollection(id: self.manager.ruleCollections[0].id)
        }
    }

    func testRejectedLayerRemovalRestoresBothSources() async throws {
        try await assertRejectedMutationRestores { await self.manager.removeLayer("WORK") }
    }

    func testRejectedBatchRestoresAllEnabledStates() async throws {
        manager.ruleCollections = [collection("First", enabled: false), collection("Second", layer: .custom("work"), enabled: false)]
        try await persistFixture()
        try await assertRejectedMutationRestores {
            await self.manager.batchEnableCollections(ids: self.manager.ruleCollections.map(\.id))
        }
    }

    func testRejectedLayerCreationRestoresPreviousRevision() async throws {
        try await assertRejectedMutationRestores { await self.manager.createLayer("Research") }
    }

    func testPendingLayerRemovalCommitsBothSourcesWithOneReload() async throws {
        var reloads = 0
        manager.onError = { XCTFail("Pending is not failure: \($0)") }
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        let removedID = manager.ruleCollections[0].id
        await manager.removeLayer("WORK")
        XCTAssertEqual(reloads, 1)
        let storedRules = try await manager.customRulesStore.loadForMutation()
        let storedCollections = await manager.ruleCollectionStore.loadCollections()
        XCTAssertTrue(storedRules.isEmpty)
        XCTAssertFalse(storedCollections.contains { $0.id == removedID })
        XCTAssertTrue(manager.customRules.isEmpty)
        XCTAssertFalse(manager.ruleCollections.contains { $0.id == removedID })
    }

    func testExternalSourceEditSurvivesFailedLayerRemoval() async throws {
        var expected: [String: Data]?
        var reloads = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloads += 1
            do {
                try Data("external edit".utf8).write(to: self.directory.appendingPathComponent("CustomRules.json"))
                expected = try self.files()
            } catch { XCTFail("Cannot inject external edit: \(error)") }
            return Self.reload(.rejected)
        }
        await manager.removeLayer("work")
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(try files(), expected)
        XCTAssertTrue(errors.first?.contains("Recovery needs attention") == true)
    }

    func testLayerCreationRecoversBeforeDuplicateCheck() async throws {
        let before = try files()
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.ruleCollections = []
        manager.customRules = []
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.applied) }
        await manager.createLayer("Work")
        XCTAssertEqual(reloads, 1, "Recover runtime, then return without creating a duplicate")
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(manager.ruleCollections.filter { $0.targetLayer == .custom("work") }.count, 1)
        XCTAssertEqual(manager.customRules.count, 1)
    }
}
