import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class CollectionSettingsRecoveryTests: KeyPathTestCase {
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
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections().map { collection in
            var disabled = collection
            disabled.isEnabled = false
            return disabled
        }
        manager.customRules = []
        try await persistFixture()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        manager = nil
        directory = nil
        try await super.tearDown()
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
        XCTAssertTrue(errors.first?.contains("Could not save") == true)
    }

    func testRejectedTapPickerRestoresOutputAndEnabledState() async throws {
        let id = UUID()
        manager.ruleCollections.append(RuleCollection(
            id: id, name: "Tap picker", summary: "", category: .custom, mappings: [], isEnabled: false,
            configuration: .tapHoldPicker(TapHoldPickerConfig(inputKey: "f13", tapOptions: [], holdOptions: [],
                                                              selectedTapOutput: "f13", selectedHoldOutput: "lctl"))
        ))
        try await persistFixture()
        try await assertRejectedMutationRestores {
            await self.manager.updateCollectionTapOutput(id: id, tapOutput: "esc")
        }
    }

    func testRejectedSequenceSettingsDoNotReportNewlyEnabled() async throws {
        try await assertRejectedMutationRestores {
            let enabled = await self.manager.updateSequencesConfig(id: RuleCollectionIdentifier.sequences, config: SequencesConfig(globalTimeout: 900))
            XCTAssertFalse(enabled)
        }
    }

    func testRejectedHomeRowSettingsRestorePrerequisitesAndCandidate() async throws {
        manager.onPrerequisiteResolution = { _ in .enableRequiredProvidersAndApply }
        try await assertRejectedMutationRestores {
            let enabled = await self.manager.updateHomeRowLayerTogglesConfig(
                id: RuleCollectionIdentifier.homeRowLayerToggles,
                config: HomeRowLayerTogglesConfig(layerAssignments: ["a": "fun"])
            )
            XCTAssertFalse(enabled)
        }
    }

    func testPendingAutoShiftSettingPreservesDisabledState() async throws {
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        let newlyEnabled = await manager.updateAutoShiftSymbolsConfig(id: RuleCollectionIdentifier.autoShiftSymbols,
                                                                      config: AutoShiftSymbolsConfig(timeoutMs: 280))
        XCTAssertFalse(newlyEnabled)
        XCTAssertEqual(reloads, 1)
        let stored = await manager.ruleCollectionStore.loadCollections()
        let collection = try XCTUnwrap(stored.first { $0.id == RuleCollectionIdentifier.autoShiftSymbols })
        XCTAssertFalse(collection.isEnabled)
        guard case let .autoShiftSymbols(config) = collection.configuration else { return XCTFail("Wrong configuration") }
        XCTAssertEqual(config.timeoutMs, 280)
    }

    func testPendingCatalogFallbackReportsNewlyEnabledOnlyAfterCommit() async throws {
        manager.ruleCollections.removeAll { $0.id == RuleCollectionIdentifier.sequences }
        try await persistFixture()
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        let enabled = await manager.updateSequencesConfig(id: RuleCollectionIdentifier.sequences, config: SequencesConfig(globalTimeout: 900))
        XCTAssertTrue(enabled)
        XCTAssertEqual(reloads, 1)
        let stored = await manager.ruleCollectionStore.loadCollections()
        let collection = try XCTUnwrap(stored.first { $0.id == RuleCollectionIdentifier.sequences })
        XCTAssertTrue(collection.isEnabled)
        guard case let .sequences(config) = collection.configuration else { return XCTFail("Wrong configuration") }
        XCTAssertEqual(config.globalTimeout, 900)
    }

    func testInterruptedRecoveryPrecedesSettingSnapshot() async throws {
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.ruleCollections = []
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.applied) }
        let enabled = await manager.updateAutoShiftSymbolsConfig(id: RuleCollectionIdentifier.autoShiftSymbols,
                                                                 config: AutoShiftSymbolsConfig(timeoutMs: 280))
        XCTAssertFalse(enabled, "Read the restored disabled collection, not catalog fallback")
        XCTAssertEqual(reloads, 2, "One recovery and one edit")
        XCTAssertFalse(try XCTUnwrap(manager.ruleCollections.first { $0.id == RuleCollectionIdentifier.autoShiftSymbols }).isEnabled)
    }

    func testPrerequisiteSaveRecoversOnceBeforeReadingEnabledState() async throws {
        let id = RuleCollectionIdentifier.homeRowMods
        let index = try XCTUnwrap(manager.ruleCollections.firstIndex { $0.id == id })
        manager.ruleCollections[index].isEnabled = true
        try await persistFixture()
        let service = manager.configurationService
        try await service.operationGate.withOperation { @MainActor permit in
            _ = try await service.stageRuleState(ruleCollections: [], customRules: [],
                                                 collectionStore: self.manager.ruleCollectionStore, customStore: self.manager.customRulesStore, mutationPermit: permit)
        }
        manager.ruleCollections = []
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.applied) }
        let newlyEnabled = await manager.updateHomeRowModsConfig(id: id, config: HomeRowModsConfig())
        XCTAssertFalse(newlyEnabled, "The recovered collection was already enabled")
        XCTAssertEqual(reloads, 2, "One recovery and one edit despite both admission checks")
        XCTAssertTrue(try XCTUnwrap(manager.ruleCollections.first { $0.id == id }).isEnabled)
    }
}
