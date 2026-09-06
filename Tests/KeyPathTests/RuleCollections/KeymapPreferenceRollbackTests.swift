import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

@MainActor
final class KeymapPreferenceRollbackTests: KeyPathTestCase {
    func testFailedChangePreservesPunctuationPreferencesAndExactPreviousCollection() async throws {
        for previouslyStored in [true, false] {
            try await withManager(blockWrites: true) { manager, preferences in
                let oldID = LogicalKeymap.dvorak.id
                manager.activeKeymapId = oldID
                manager.keymapIncludesPunctuation = false
                var previous = try XCTUnwrap(KeymapMappingGenerator.generateCollection(for: oldID, includePunctuation: false))
                previous.name = "Customized Dvorak"
                manager.ruleCollections = [previous]
                if previouslyStored {
                    preferences.set(oldID, forKey: "activeKeymapId")
                    preferences.set(false, forKey: "keymapIncludesPunctuation")
                }
                var reloadCount = 0
                manager.onRulesChanged = {
                    reloadCount += 1
                    return ReloadResult(success: true, response: nil, errorMessage: nil, protocol: nil)
                }
                _ = await manager.setActiveKeymap(LogicalKeymap.colemak.id, includePunctuation: true)
                XCTAssertEqual(manager.activeKeymapId, oldID)
                XCTAssertFalse(manager.keymapIncludesPunctuation)
                XCTAssertEqual(manager.ruleCollections.map(\.id), [previous.id])
                XCTAssertEqual(manager.ruleCollections.first?.name, previous.name)
                XCTAssertEqual(manager.ruleCollections.first?.mappings, previous.mappings)
                XCTAssertEqual(reloadCount, 0)
                if previouslyStored {
                    XCTAssertEqual(preferences.string(forKey: "activeKeymapId"), oldID)
                    XCTAssertEqual(preferences.object(forKey: "keymapIncludesPunctuation") as? Bool, false)
                } else {
                    XCTAssertNil(preferences.object(forKey: "activeKeymapId"))
                    XCTAssertNil(preferences.object(forKey: "keymapIncludesPunctuation"))
                }
            }
        }
    }

    func testFailedOverlaySelectionRestoresDisplayAndPreservesOtherLayoutPreferences() async throws {
        for changesPunctuation in [false, true] {
            try await withManager(blockWrites: true) { manager, preferences in
                let oldID = LogicalKeymap.dvorak.id
                let requestedID = changesPunctuation ? oldID : LogicalKeymap.colemak.id
                manager.activeKeymapId = oldID
                manager.keymapIncludesPunctuation = false
                manager.ruleCollections = try [XCTUnwrap(KeymapMappingGenerator.generateCollection(for: oldID, includePunctuation: false))]
                preferences.set(requestedID, forKey: KeymapPreferences.keymapIdKey)
                let store = KeymapPreferences.updatedIncludePunctuationStore(
                    from: "{\"unrelated-layout\":true}", keymapId: requestedID, includePunctuation: changesPunctuation
                )
                preferences.set(store, forKey: KeymapPreferences.includePunctuationStoreKey)
                _ = await manager.setActiveKeymap(requestedID, includePunctuation: changesPunctuation)
                XCTAssertEqual(preferences.string(forKey: KeymapPreferences.keymapIdKey), oldID)
                XCTAssertFalse(KeymapPreferences.includePunctuation(for: oldID, userDefaults: preferences))
                XCTAssertTrue(KeymapPreferences.includePunctuation(for: "unrelated-layout", userDefaults: preferences))
            }
        }
    }

    func testFailedSelectionDoesNotOverwriteANewerDisplayChoice() throws {
        let suite = "KeymapRollbackTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(LogicalKeymap.colemak.id, forKey: KeymapPreferences.keymapIdKey)
        KeymapPreferences.restoreFailedSelection(
            attemptedID: LogicalKeymap.dvorak.id, attemptedPunctuation: true,
            previousID: LogicalKeymap.qwertyUSId, previousPunctuation: false,
            userDefaults: preferences
        )
        XCTAssertEqual(preferences.string(forKey: KeymapPreferences.keymapIdKey), LogicalKeymap.colemak.id)
        XCTAssertNil(preferences.object(forKey: KeymapPreferences.includePunctuationStoreKey))
    }

    func testFailedPunctuationEditIsRestoredAfterSelectingAnotherLayout() throws {
        let suite = "KeymapRollbackTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(LogicalKeymap.colemak.id, forKey: KeymapPreferences.keymapIdKey)
        preferences.set(KeymapPreferences.updatedIncludePunctuationStore(
            from: "{}", keymapId: LogicalKeymap.dvorak.id, includePunctuation: true
        ), forKey: KeymapPreferences.includePunctuationStoreKey)
        KeymapPreferences.restoreFailedSelection(
            attemptedID: LogicalKeymap.dvorak.id, attemptedPunctuation: true,
            previousID: LogicalKeymap.dvorak.id, previousPunctuation: false,
            userDefaults: preferences
        )
        XCTAssertEqual(preferences.string(forKey: KeymapPreferences.keymapIdKey), LogicalKeymap.colemak.id)
        XCTAssertFalse(KeymapPreferences.includePunctuation(for: LogicalKeymap.dvorak.id, userDefaults: preferences))
    }

    func testPendingSavePersistsTheSelectedKeymapAndPunctuation() async throws {
        try await withManager(blockWrites: false) { manager, preferences in
            manager.onRulesChanged = {
                ReloadResult(success: false, response: nil, errorMessage: "offline", protocol: nil, disposition: .pending)
            }
            _ = await manager.setActiveKeymap(LogicalKeymap.dvorak.id, includePunctuation: true)
            XCTAssertEqual(preferences.string(forKey: "activeKeymapId"), LogicalKeymap.dvorak.id)
            XCTAssertTrue(preferences.bool(forKey: "keymapIncludesPunctuation"))
            let stored = await manager.ruleCollectionStore.loadCollections()
            XCTAssertTrue(stored.contains { $0.id == RuleCollectionIdentifier.keymapLayout })
            manager.activeKeymapId = LogicalKeymap.qwertyUSId
            manager.keymapIncludesPunctuation = false
            manager.restoreKeymapState()
            XCTAssertEqual(manager.activeKeymapId, LogicalKeymap.dvorak.id)
            XCTAssertTrue(manager.keymapIncludesPunctuation)
        }
    }

    func testRejectedReloadRestoresExactFilesAndPreferencesBeforeFeedback() async throws {
        try await withManager(blockWrites: false) { manager, preferences in
            _ = await manager.setActiveKeymap(LogicalKeymap.dvorak.id, includePunctuation: false)
            let originalCollections = manager.ruleCollections
            let before = try await self.files(manager)
            preferences.set(LogicalKeymap.colemak.id, forKey: KeymapPreferences.keymapIdKey)
            preferences.set(
                KeymapPreferences.updatedIncludePunctuationStore(from: "{}", keymapId: LogicalKeymap.colemak.id, includePunctuation: true),
                forKey: KeymapPreferences.includePunctuationStoreKey
            )
            var reloads = 0
            var errors = 0
            manager.onRulesChanged = {
                reloads += 1
                if reloads == 2 {
                    do { let restored = try await self.files(manager); XCTAssertEqual(restored, before) }
                    catch { XCTFail("\(error)") }
                }
                return Self.reload(reloads == 1 ? .rejected : .applied)
            }
            manager.onError = { _ in
                errors += 1
                XCTAssertEqual(manager.activeKeymapId, LogicalKeymap.dvorak.id)
                XCTAssertFalse(manager.keymapIncludesPunctuation)
                XCTAssertEqual(manager.ruleCollections, originalCollections)
                XCTAssertEqual(preferences.string(forKey: KeymapPreferences.keymapIdKey), LogicalKeymap.dvorak.id)
            }
            _ = await manager.setActiveKeymap(LogicalKeymap.colemak.id, includePunctuation: true)
            XCTAssertEqual(reloads, 2)
            XCTAssertEqual(errors, 1)
            let after = try await self.files(manager)
            XCTAssertEqual(after, before)
            XCTAssertEqual(preferences.string(forKey: "activeKeymapId"), LogicalKeymap.dvorak.id)
        }
    }

    func testExternalConfigDuringFailedKeymapSaveIsPreserved() async throws {
        try await withManager(blockWrites: false) { manager, _ in
            _ = await manager.setActiveKeymap(LogicalKeymap.dvorak.id, includePunctuation: false)
            let url = URL(fileURLWithPath: manager.configurationService.configurationPath)
            let external = ";; external editor revision"
            var reloads = 0
            var message: String?
            manager.onError = { message = $0 }
            manager.onRulesChanged = {
                reloads += 1
                do { try external.write(to: url, atomically: true, encoding: .utf8) }
                catch { XCTFail("\(error)") }
                return Self.reload(.rejected)
            }
            _ = await manager.setActiveKeymap(LogicalKeymap.colemak.id, includePunctuation: true)
            XCTAssertEqual(reloads, 1)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), external)
            XCTAssertEqual(manager.activeKeymapId, LogicalKeymap.dvorak.id)
            XCTAssertTrue(message?.contains("Recovery needs attention") == true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: RecoverableRuleWrite.journalURL(url.deletingLastPathComponent()).path))
        }
    }

    func testInterruptedStateRecoversBeforeKeymapSnapshot() async throws {
        try await withManager(blockWrites: false) { manager, _ in
            manager.ruleCollections = RuleCollectionCatalog().defaultCollections().map { collection in
                var disabled = collection
                disabled.isEnabled = false
                return disabled
            }
            manager.customRules = [CustomRule(input: "f20", action: .keystroke(key: "f19"), createdAt: Date(timeIntervalSince1970: 42))]
            _ = await manager.setActiveKeymap(LogicalKeymap.dvorak.id, includePunctuation: false)
            let originalRules = manager.customRules
            let before = try await self.files(manager)
            let service = manager.configurationService
            try await service.operationGate.withOperation { @MainActor permit in
                _ = try await service.stageRuleState(ruleCollections: [], customRules: [], collectionStore: manager.ruleCollectionStore,
                                                     customStore: manager.customRulesStore, mutationPermit: permit)
            }
            manager.customRules = []
            var reloads = 0
            manager.onRulesChanged = {
                reloads += 1
                if reloads != 2 {
                    do { let restored = try await self.files(manager); XCTAssertEqual(restored, before) }
                    catch { XCTFail("\(error)") }
                }
                return Self.reload(reloads == 2 ? .rejected : .applied)
            }
            _ = await manager.setActiveKeymap(LogicalKeymap.colemak.id, includePunctuation: true)
            XCTAssertEqual(reloads, 3, "Recover old operation, reject new edit, then recover the old layout")
            XCTAssertEqual(manager.customRules, originalRules)
            XCTAssertEqual(manager.activeKeymapId, LogicalKeymap.dvorak.id)
            let after = try await self.files(manager)
            XCTAssertEqual(after, before)
        }
    }

    func testRejectedReloadPreservesNewerOverlaySelection() async throws {
        try await withManager(blockWrites: false) { manager, preferences in
            _ = await manager.setActiveKeymap(LogicalKeymap.dvorak.id, includePunctuation: false)
            preferences.set(LogicalKeymap.colemak.id, forKey: KeymapPreferences.keymapIdKey)
            preferences.set(
                KeymapPreferences.updatedIncludePunctuationStore(from: "{}", keymapId: LogicalKeymap.colemak.id, includePunctuation: true),
                forKey: KeymapPreferences.includePunctuationStoreKey
            )
            var reloads = 0
            manager.onRulesChanged = {
                reloads += 1
                if reloads == 1 { preferences.set(LogicalKeymap.systemId, forKey: KeymapPreferences.keymapIdKey) }
                return Self.reload(reloads == 1 ? .rejected : .applied)
            }
            _ = await manager.setActiveKeymap(LogicalKeymap.colemak.id, includePunctuation: true)
            XCTAssertEqual(manager.activeKeymapId, LogicalKeymap.dvorak.id)
            XCTAssertEqual(preferences.string(forKey: KeymapPreferences.keymapIdKey), LogicalKeymap.systemId)
        }
    }

    private static func reload(_ disposition: ReloadDisposition) -> ReloadResult {
        ReloadResult(success: disposition == .applied, response: nil, errorMessage: "injected \(disposition)", protocol: nil, disposition: disposition)
    }

    private func files(_ manager: RuleCollectionsManager) async throws -> [String: Data] {
        let paths = await ["config": URL(fileURLWithPath: manager.configurationService.configurationPath),
                           "collections": manager.ruleCollectionStore.persistenceURL,
                           "customRules": manager.customRulesStore.persistenceURL]
        return try paths.mapValues { try Data(contentsOf: $0) }
    }

    private func withManager(blockWrites: Bool, test: @MainActor (RuleCollectionsManager, UserDefaults) async throws -> Void) async throws {
        let suite = "KeymapRollbackTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configDirectory = directory.appendingPathComponent("config")
        if blockWrites { try "blocked".write(to: configDirectory, atomically: true, encoding: .utf8) }
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService(configDirectory: configDirectory.path, ruleCollectionStore: collections, customRulesStore: rules)
        let manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service, keymapPreferences: preferences)
        try await test(manager, preferences)
    }
}
