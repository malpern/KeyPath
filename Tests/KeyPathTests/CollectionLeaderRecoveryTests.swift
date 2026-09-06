import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class CollectionLeaderRecoveryTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!
    private var originalLeaderPreference: LeaderKeyPreference!

    override func setUp() async throws {
        try await super.setUp()
        originalLeaderPreference = PreferencesService.shared.leaderKeyPreference
        PreferencesService.shared.leaderKeyPreference = .default
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.ruleCollections = RuleCollectionCatalog().defaultCollections().map { collection in
            var copy = collection
            copy.isEnabled = copy.id == RuleCollectionIdentifier.leaderKey
            return copy
        }
        manager.customRules = []
        try await service.saveRuleState(ruleCollections: manager.ruleCollections, customRules: [], collectionStore: collections, customStore: rules)
    }

    override func tearDown() async throws {
        if let originalLeaderPreference { PreferencesService.shared.leaderKeyPreference = originalLeaderPreference }
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
        let leaderBefore = PreferencesService.shared.leaderKeyPreference
        var reloads = 0
        var errors: [String] = []
        manager.onError = {
            errors.append($0)
            XCTAssertEqual(PreferencesService.shared.leaderKeyPreference, leaderBefore, "Restore preferences before error feedback")
        }
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
        XCTAssertEqual(PreferencesService.shared.leaderKeyPreference, leaderBefore)
        XCTAssertEqual(errors.count, 1)
    }

    func testRejectedCollectionToggleRestoresDisabledState() async throws {
        try await assertRejectedMutationRestores {
            let enabled = await self.manager.toggleCollection(id: RuleCollectionIdentifier.homeRowMods, isEnabled: true, bypassOwnershipCheck: true)
            XCTAssertFalse(enabled)
        }
    }

    func testRejectedLeaderToggleRestoresPreferenceAndCollections() async throws {
        try await assertRejectedMutationRestores {
            let enabled = await self.manager.toggleCollection(id: RuleCollectionIdentifier.leaderKey, isEnabled: false, bypassOwnershipCheck: true)
            XCTAssertFalse(enabled)
        }
    }

    func testRejectedLeaderPickerRestoresSelectionBeforeNestedMutation() async throws {
        try await assertRejectedMutationRestores {
            await self.manager.updateCollectionOutput(id: RuleCollectionIdentifier.leaderKey, output: "f18")
        }
    }

    func testRejectedDirectLeaderEditRestoresPreferenceAndActivators() async throws {
        try await assertRejectedMutationRestores { await self.manager.updateLeaderKey("f18") }
    }

    func testRejectedReplacementRestoresOriginalCollectionSet() async throws {
        try await assertRejectedMutationRestores { await self.manager.replaceCollections([]) }
    }

    func testRejectedReplacementRestoresReconciledLeaderPreference() async throws {
        var replacement = manager.ruleCollections
        let index = try XCTUnwrap(replacement.firstIndex { $0.id == RuleCollectionIdentifier.leaderKey })
        replacement[index].configuration.updateSelectedOutput("f18")
        try await assertRejectedMutationRestores { await self.manager.replaceCollections(replacement) }
    }

    func testPendingLeaderPickerCommitsSelectionAndPreference() async throws {
        var reloads = 0
        manager.onRulesChanged = { reloads += 1; return Self.reload(.pending) }
        await manager.updateCollectionOutput(id: RuleCollectionIdentifier.leaderKey, output: "f18")
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(PreferencesService.shared.leaderKeyPreference.key, "f18")
        let stored = await manager.ruleCollectionStore.loadCollections()
        let leader = try XCTUnwrap(stored.first { $0.id == RuleCollectionIdentifier.leaderKey })
        XCTAssertEqual(leader.configuration.singleKeyPickerConfig?.selectedOutput, "f18")
    }

    func testFailedLeaderEditPreservesNewerPreference() async throws {
        let before = try files()
        var reloads = 0
        var errors: [String] = []
        manager.onError = { errors.append($0) }
        manager.onRulesChanged = {
            reloads += 1
            if reloads == 1 {
                PreferencesService.shared.leaderKeyPreference = LeaderKeyPreference(key: "f17", targetLayer: .navigation, enabled: true)
            }
            return Self.reload(reloads == 1 ? .rejected : .applied)
        }
        await manager.updateLeaderKey("f18")
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(try files(), before)
        XCTAssertEqual(PreferencesService.shared.leaderKeyPreference.key, "f17")
        XCTAssertTrue(errors.first?.contains("newer leader-key preference was preserved") == true)
    }
}
