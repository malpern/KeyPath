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
