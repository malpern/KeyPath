import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
import Testing

/// Static structural asserts on the default collection catalog.
///
/// Today's config generator silently resolves two kinds of collisions by
/// keeping the first-registered definition:
/// * Two collections declaring the same `momentaryActivator(input, sourceLayer)`.
/// * Two collections mapping the same input key in the same `targetLayer`.
///
/// Either can mask a real product bug ("I added a pack and it doesn't work,
/// another pack just silently took the key"). These tests surface the
/// collision at build time instead of letting it fail silently at runtime.
///
/// ~5ms total, no kanata binary needed.
@Suite("RuleCollection Collision Detection")
struct RuleCollectionCollisionTests {
    private var collections: [RuleCollection] {
        RuleCollectionCatalog().defaultCollections()
    }

    // MARK: - Catalog sanity

    @Test("Catalog returns a non-empty set of collections")
    func catalogNonEmpty() {
        #expect(!collections.isEmpty)
    }

    @Test("Every collection has a unique ID")
    func collectionIDsUnique() {
        let ids = collections.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate collection IDs found")
    }

    @Test("Every collection has a non-empty name")
    func collectionNamesNonEmpty() {
        for collection in collections {
            #expect(!collection.name.isEmpty, "Collection \(collection.id) has an empty name")
        }
    }

    @Test("Every collection with mappings has a non-empty target layer name")
    func targetLayerNamesValid() {
        for collection in collections where !collection.mappings.isEmpty {
            #expect(!collection.targetLayer.kanataName.isEmpty,
                    "\(collection.name) has mappings but empty target layer")
        }
    }

    // MARK: - Activator uniqueness

    @Test("No two collections share an activator (except known nav providers)")
    func noTwoCollectionsShareAnActivator() {
        let navProviderIDs: Set<UUID> = [
            RuleCollectionIdentifier.vimNavigation,
            RuleCollectionIdentifier.neovimTerminal,
        ]

        var claimed: [String: String] = [:]
        var collisions: [(key: String, existing: String, incoming: String)] = []

        for collection in collections {
            guard let activator = collection.momentaryActivator else { continue }
            let key = "\(activator.sourceLayer.kanataName):\(activator.input.lowercased())"
            if let existing = claimed[key] {
                if navProviderIDs.contains(collection.id),
                   let existingCollection = collections.first(where: { $0.name == existing }),
                   navProviderIDs.contains(existingCollection.id)
                {
                    continue
                }
                collisions.append((key, existing, collection.name))
            } else {
                claimed[key] = collection.name
            }
        }

        #expect(collisions.isEmpty,
                "Duplicate momentaryActivators: \(collisions.map { "\($0.key): \($0.existing) ↔ \($0.incoming)" })")
    }

    // MARK: - Mapping uniqueness per target layer

    @Test("No two collections map the same input in the same layer with different outputs")
    func noTwoCollectionsMapTheSameInputInTheSameLayer() {
        var claimed: [String: (name: String, output: String)] = [:]
        var collisions: [String] = []

        for collection in collections {
            let layerKey = collection.targetLayer.kanataName
            for mapping in collection.mappings {
                if mapping.input.contains(" ") { continue }
                let key = "\(layerKey):\(mapping.input.lowercased())"
                if let existing = claimed[key] {
                    if existing.output != mapping.action.outputString {
                        collisions.append(
                            "\(key): \(existing.name)(\(existing.output)) ↔ \(collection.name)(\(mapping.action.outputString))"
                        )
                    }
                } else {
                    claimed[key] = (collection.name, mapping.action.outputString)
                }
            }
        }

        #expect(collisions.isEmpty, "Input-key collisions: \(collisions)")
    }

    // MARK: - Mapping structural integrity

    @Test("Every mapping has a non-empty input key")
    func mappingInputsNonEmpty() {
        for collection in collections {
            for mapping in collection.mappings {
                #expect(!mapping.input.isEmpty, "\(collection.name) has a mapping with empty input")
            }
        }
    }

    @Test("No collection has duplicate input keys within its own mappings")
    func noDuplicateInputsWithinCollection() {
        for collection in collections {
            let nonChordInputs = collection.mappings
                .map(\.input)
                .filter { !$0.contains(" ") }
                .map { $0.lowercased() }
            let unique = Set(nonChordInputs)
            #expect(nonChordInputs.count == unique.count,
                    "\(collection.name) has duplicate input keys")
        }
    }
}
