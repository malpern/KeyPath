import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Helpers for the config-correctness matrix tests.
///
/// The same pattern — load the catalog, find a collection by id, enable it,
/// generate a kanata config — was duplicated across ConfigGoldenFileTests,
/// ConfigValidationTests, and ConfigGenerationEndToEndTests. These helpers
/// collapse it to one line, with a `mutate` closure for per-option matrices.
@MainActor
enum MatrixTestHelpers {
    /// Enable a single catalog collection and return the generated kanata config.
    ///
    /// - Parameters:
    ///   - id: The collection's `RuleCollectionIdentifier` UUID.
    ///   - mutate: Optional in-place mutation applied *after* enabling, before
    ///     generation. Use for per-option matrices (flip a preset, change a
    ///     timing, etc.).
    /// - Returns: The kanata `.kbd` config string. Returns the default catalog
    ///   config unchanged if no collection matches `id` (helpers should fail
    ///   loudly at the call site, not silently in the helper).
    static func enabledCollectionConfig(
        _ id: UUID,
        mutate: ((inout RuleCollection) -> Void)? = nil
    ) -> String {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == id }) {
            collections[idx].isEnabled = true
            mutate?(&collections[idx])
        }
        return KanataConfiguration.generateFromCollections(collections)
    }

    /// Enable the catalog collection associated with a pack, return its config.
    ///
    /// Mirrors the pattern in ConfigGoldenFileTests.testVimNavigation_Golden
    /// where the collection ID is looked up via PackRegistry rather than
    /// hardcoded.
    ///
    /// - Returns: nil if the pack or its associated collection cannot be
    ///   resolved — callers should `XCTUnwrap` or guard.
    static func enabledPackConfig(_ packID: String) -> String? {
        guard let pack = PackRegistry.pack(id: packID),
              let collectionID = pack.associatedCollectionID
        else {
            return nil
        }
        return enabledCollectionConfig(collectionID)
    }
}
