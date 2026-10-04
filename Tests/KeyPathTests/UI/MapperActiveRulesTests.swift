@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

/// Tests for the mapper sidebar active rules footer logic.
@MainActor
final class MapperActiveRulesTests: XCTestCase {
    func testDefaultEnabledCollectionsOnlyIncludesStandardFunctionKeys() {
        let defaults = RuleCollectionCatalog().defaultCollections()
        let enabled = defaults.filter(\.isEnabled)
        XCTAssertEqual(enabled.map(\.id), [RuleCollectionIdentifier.macFunctionKeys])
        XCTAssertEqual(enabled.first?.functionKeyMode, .function)
    }

    func testUserFacingPacks_ExcludesSystemDefaults() {
        let defaults = RuleCollectionCatalog().defaultCollections()
        let enabledIDs = Set(defaults.filter(\.isEnabled).map(\.id))

        // macOS Function Keys is system default — should not appear as user-facing
        let userFacingPacks = PackRegistry.starterKit.filter { pack in
            guard let collectionID = pack.associatedCollectionID else { return false }
            guard !pack.visualOnly else { return false }
            return enabledIDs.contains(collectionID)
        }

        let hasSystemPack = userFacingPacks.contains { $0.id == "com.keypath.pack.macos-function-keys" }
        XCTAssertFalse(hasSystemPack, "System packs should not appear in user-facing list")
    }

    func testHasCustomized_FalseOnDefaults() {
        let defaults = RuleCollectionCatalog().defaultCollections()
        let defaultEnabledIDs = Set(defaults.filter(\.isEnabled).map(\.id))
        let currentEnabledIDs = Set(defaults.filter(\.isEnabled).map(\.id))

        XCTAssertEqual(defaultEnabledIDs, currentEnabledIDs,
                       "Same set means not customized")
    }

    func testHasCustomized_TrueWhenPackAdded() {
        var collections = RuleCollectionCatalog().defaultCollections()
        let defaultEnabledIDs = Set(collections.filter(\.isEnabled).map(\.id))

        // Enable an extra pack
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            collections[idx].isEnabled = true
        }
        let currentEnabledIDs = Set(collections.filter(\.isEnabled).map(\.id))

        XCTAssertNotEqual(defaultEnabledIDs, currentEnabledIDs,
                          "Enabling a new pack should count as customized")
    }

    func testHasCustomized_TrueWhenPackRemoved() {
        var collections = RuleCollectionCatalog().defaultCollections()
        let defaultEnabledIDs = Set(collections.filter(\.isEnabled).map(\.id))

        // Disable a default pack
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.macFunctionKeys }) {
            collections[idx].isEnabled = false
        }
        let currentEnabledIDs = Set(collections.filter(\.isEnabled).map(\.id))

        XCTAssertNotEqual(defaultEnabledIDs, currentEnabledIDs,
                          "Disabling a default pack should count as customized")
    }

    func testMerchandisingThreshold_Under6ShowsHero() {
        // Default user-facing packs (excluding the macOS Function Keys system default)
        // must stay below the merchandising-hero threshold, which production sets at
        // `< 6` (OverlayInspectorPanel+CustomRules.swift). The conservative fresh
        // profile enables only the system function-key collection.
        let defaults = RuleCollectionCatalog().defaultCollections()
        let enabledIDs = Set(defaults.filter(\.isEnabled).map(\.id))

        let userFacingPacks = PackRegistry.starterKit.filter { pack in
            guard let collectionID = pack.associatedCollectionID else { return false }
            guard !pack.visualOnly else { return false }
            return enabledIDs.contains(collectionID)
        }

        XCTAssertLessThan(userFacingPacks.count, 6,
                          "Default user-facing pack count should be under 6 for merchandising")
    }
}
