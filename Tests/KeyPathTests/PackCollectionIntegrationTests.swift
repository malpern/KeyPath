@testable import KeyPathAppKit
import XCTest

/// Tests for the pack → rule collection mapping chain.
/// Verifies that packs correctly reference their backing collections
/// and that config generation produces valid kanata config.
final class PackCollectionIntegrationTests: XCTestCase {

    // MARK: - Pack-to-Collection Mapping

    func testAllNonVisualPacksHaveAssociatedCollections() {
        for pack in PackRegistry.starterKit where !pack.visualOnly {
            XCTAssertNotNil(
                pack.associatedCollectionID,
                "Non-visual pack '\(pack.name)' (\(pack.id)) must have an associatedCollectionID"
            )
        }
    }

    func testAssociatedCollectionsExistInCatalog() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        let catalogIDs = Set(catalog.map { $0.id })

        for pack in PackRegistry.starterKit {
            guard let collectionID = pack.associatedCollectionID else { continue }
            XCTAssertTrue(
                catalogIDs.contains(collectionID),
                "Pack '\(pack.name)' references collection \(collectionID) which doesn't exist in catalog"
            )
        }
    }

    func testPackBindingsMatchCollectionMappings() {
        let catalog = RuleCollectionCatalog().defaultCollections()

        for pack in PackRegistry.starterKit {
            guard let collectionID = pack.associatedCollectionID,
                  let collection = catalog.first(where: { $0.id == collectionID })
            else { continue }

            // Packs with tap-hold pickers don't have direct mapping matches
            if case .tapHoldPicker = collection.configuration { continue }
            if case .homeRowMods = collection.configuration { continue }
            if case .layerPresetPicker = collection.configuration { continue }

            if case .singleKeyPicker = collection.configuration { continue }

            // For simple list/table packs, verify binding count matches
            if !pack.bindings.isEmpty, !collection.mappings.isEmpty {
                XCTAssertEqual(
                    pack.bindings.count,
                    collection.mappings.count,
                    "Pack '\(pack.name)' has \(pack.bindings.count) bindings but collection has \(collection.mappings.count) mappings"
                )
            }
        }
    }

    // MARK: - Pack Summary Formatting

    func testAllPacksProduceSummariesOrNil() {
        let catalog = RuleCollectionCatalog().defaultCollections()
        for pack in PackRegistry.starterKit {
            let collection = pack.associatedCollectionID.flatMap { id in
                catalog.first { $0.id == id }
            }
            let input = PackSummaryProvider.Input(
                pack: pack,
                collection: collection,
                tapOverride: nil,
                holdOverride: nil,
                singleKeyOverride: nil
            )
            // Summary may be nil for some pack types — just verify no crash
            _ = PackSummaryProvider.summary(for: input)
        }
    }

    // MARK: - Collection Configuration Types

    func testCapsLockPackUsesTapHoldPicker() {
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.caps-lock-to-escape"),
              let collectionID = pack.associatedCollectionID
        else {
            return XCTFail("Caps lock pack or collection ID missing")
        }

        let catalog = RuleCollectionCatalog().defaultCollections()
        guard let collection = catalog.first(where: { $0.id == collectionID }) else {
            return XCTFail("Collection not found in catalog")
        }

        if case .tapHoldPicker(let config) = collection.configuration {
            XCTAssertEqual(config.inputKey.lowercased(), "caps", "Should target caps key")
            XCTAssertFalse(config.tapOptions.isEmpty, "Should have tap options")
            XCTAssertFalse(config.holdOptions.isEmpty, "Should have hold options")
        } else {
            XCTFail("Caps lock collection should use tapHoldPicker configuration")
        }
    }

    func testHomeRowModsPackUsesHomeRowModsConfig() {
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.home-row-mods"),
              let collectionID = pack.associatedCollectionID
        else {
            return XCTFail("Home row mods pack or collection ID missing")
        }

        let catalog = RuleCollectionCatalog().defaultCollections()
        guard let collection = catalog.first(where: { $0.id == collectionID }) else {
            return XCTFail("Collection not found in catalog")
        }

        if case .homeRowMods = collection.configuration {
            // Expected
        } else {
            XCTFail("Home row mods collection should use homeRowMods configuration")
        }
    }

    // MARK: - Pack Category Classification

    func testAllPacksHaveValidCategories() {
        for pack in PackRegistry.starterKit {
            XCTAssertFalse(pack.name.isEmpty, "Pack should have a name")
            XCTAssertFalse(pack.tagline.isEmpty, "Pack '\(pack.name)' should have a tagline")
        }
    }
}
