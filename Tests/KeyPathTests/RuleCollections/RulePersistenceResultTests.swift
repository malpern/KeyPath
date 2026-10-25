import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class RulePersistenceResultTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!
    private var service: ConfigurationService!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        service = ConfigurationService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.ruleCollections = [collection("Test", output: "b")]
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        manager = nil
        service = nil
        directory = nil
        try await super.tearDown()
    }

    private func collection(_ name: String, output: String) -> RuleCollection {
        RuleCollection(name: name, summary: name, category: .productivity,
                       mappings: [KeyMapping(input: "a", action: .keystroke(key: output))], isEnabled: true)
    }

    func testPersistenceRetainsEveryReloadDispositionAndOccursBeforeCallback() async {
        for disposition: ReloadDisposition in [.applied, .pending, .rejected, .failed] {
            var reloadCount = 0
            manager.onRulesChanged = {
                reloadCount += 1
                XCTAssertTrue(FileManager.default.fileExists(atPath: self.service.configurationPath))
                let stored = await self.manager.ruleCollectionStore.loadCollections()
                XCTAssertTrue(stored.contains { $0.name == "Test" })
                return ReloadResult(success: disposition == .applied, response: "response", errorMessage: "detail", protocol: nil, disposition: disposition)
            }
            let result = await manager.persistRules()
            guard case let .persisted(reloadResult) = result else {
                return XCTFail("Expected persistence to complete for \(disposition)")
            }
            XCTAssertTrue(result.didPersist)
            XCTAssertEqual(reloadResult?.disposition, disposition)
            XCTAssertEqual(reloadResult?.response, "response")
            XCTAssertEqual(reloadResult?.errorMessage, "detail")
            XCTAssertEqual(reloadCount, 1)
        }
    }

    func testCompatibilityBooleanStillMeansPersistedAfterRejectedReload() async {
        manager.onRulesChanged = {
            ReloadResult(success: false, response: nil, errorMessage: "rejected", protocol: nil, disposition: .rejected)
        }
        let persisted = await manager.regenerateConfigFromCollections()
        XCTAssertTrue(persisted, "Do not trigger partial caller rollback before transaction migration")
    }

    func testSkippedAndAbsentCallbacksDoNotInventApplicationResult() async {
        manager.onRulesChanged = {
            XCTFail("Explicitly skipped reload must not run")
            return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil)
        }
        let skipped = await manager.persistRules(skipReload: true)
        manager.onRulesChanged = nil
        let absent = await manager.persistRules()
        for result in [skipped, absent] {
            guard case let .persisted(reloadResult) = result else {
                return XCTFail("Persistence should still complete")
            }
            XCTAssertNil(reloadResult)
        }
    }

    func testPersistenceFailureRetainsErrorWithoutCallingReload() async throws {
        try FileManager.default.removeItem(at: directory)
        try "blocked".write(to: directory, atomically: true, encoding: .utf8)
        manager.onRulesChanged = {
            XCTFail("Persistence failure must not reload")
            return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil)
        }
        let result = await manager.persistRules()
        guard case let .failed(error) = result else { return XCTFail("Expected persistence failure") }
        XCTAssertFalse(result.didPersist)
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }

    func testConflictRetryPreservesReloadResultWithoutSecondAttempt() async {
        let first = collection("First", output: "b")
        let second = collection("Second", output: "c")
        manager.ruleCollections = [first, second]
        manager.onMappingConflictResolution = { _ in second.id }
        var reloadCount = 0
        manager.onRulesChanged = {
            reloadCount += 1
            return ReloadResult(success: false, response: nil, errorMessage: "pending detail", protocol: nil, disposition: .pending)
        }
        let conflict = KeyPathError.configuration(.mappingConflicts(conflicts: [
            KeyPathError.MappingConflictInfo(inputKey: "a", layer: "Base", conflictingCollections: [first.name, second.name])
        ]))
        let result = await manager.tryResolveMappingConflict(conflict, skipReload: false, depth: 0)
        guard case let .persisted(reloadResult)? = result else { return XCTFail("Conflict retry should persist") }
        XCTAssertEqual(reloadResult?.disposition, .pending)
        XCTAssertEqual(reloadResult?.errorMessage, "pending detail")
        XCTAssertEqual(reloadCount, 1)
        XCTAssertEqual(manager.ruleCollections.first { $0.id == second.id }?.isEnabled, false)
    }
}
