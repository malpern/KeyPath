@testable import KeyPathAppKit
import XCTest

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
final class RuleCollectionCollisionTests: XCTestCase {
    private var collections: [RuleCollection] {
        RuleCollectionCatalog().defaultCollections()
    }

    // MARK: - Activator uniqueness

    func testNoTwoCollectionsShareAnActivator() {
        // Intentionally-overlapping activators. The nav-providing collections
        // (Vim Navigation, Neovim Terminal) both use Space as Leader — a
        // user is meant to pick one, so the shared activator is by design
        // rather than a bug.
        let navProviderIDs: Set<UUID> = [
            RuleCollectionIdentifier.vimNavigation,
            RuleCollectionIdentifier.neovimTerminal
        ]

        // Key: "<sourceLayer>:<input>". Value: first-registering collection name.
        var claimed: [String: String] = [:]
        var collisions: [(key: String, existing: String, incoming: String)] = []

        for collection in collections {
            guard let activator = collection.momentaryActivator else { continue }
            let key = "\(activator.sourceLayer.kanataName):\(activator.input.lowercased())"
            if let existing = claimed[key] {
                // Allow overlap among known mutually-exclusive nav providers.
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

        XCTAssertTrue(collisions.isEmpty,
                      "Duplicate momentaryActivators detected:\n" +
                      collisions.map { "  \($0.key): \($0.existing) ↔ \($0.incoming)" }.joined(separator: "\n"))
    }

    // MARK: - Mapping uniqueness per target layer

    func testNoTwoCollectionsMapTheSameInputInTheSameLayer() {
        // Key: "<targetLayer>:<input>". Value: (collection name, output).
        var claimed: [String: (name: String, output: String)] = [:]
        var collisions: [String] = []

        for collection in collections {
            let layerKey = collection.targetLayer.kanataName
            for mapping in collection.mappings {
                // Space-separated chord inputs aren't "same input" — they
                // land in defchordsv2 separately. Skip them here.
                if mapping.input.contains(" ") { continue }
                let key = "\(layerKey):\(mapping.input.lowercased())"
                if let existing = claimed[key] {
                    // Same output across two collections is fine (both agree).
                    if existing.output != mapping.output {
                        collisions.append(
                            "\(key): \(existing.name)(\(existing.output)) ↔ " +
                                "\(collection.name)(\(mapping.output))"
                        )
                    }
                } else {
                    claimed[key] = (collection.name, mapping.output)
                }
            }
        }

        XCTAssertTrue(collisions.isEmpty,
                      "Input-key collisions in the same target layer:\n" +
                      collisions.joined(separator: "\n"))
    }
}
