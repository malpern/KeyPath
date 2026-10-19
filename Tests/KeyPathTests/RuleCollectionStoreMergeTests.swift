import Foundation
@testable import KeyPathAppKit
import KeyPathRulesCore
@preconcurrency import XCTest

/// An existing profile missing an entry gets runnable function keys and nothing else.
final class RuleCollectionStoreMergeTests: XCTestCase {
    func testLostFunctionKeyEntryUsesSessionSafeFunctionModeAndNewEntriesStayOff() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))

        let catalog = RuleCollectionCatalog()
        let originals = catalog.originalCollections()
        let kept = try XCTUnwrap(originals.first { $0.id != RuleCollectionIdentifier.macFunctionKeys })
        try await store.encodedCollections([kept]).write(to: store.persistenceURL)

        let loaded = await store.loadCollections()
        let original = try XCTUnwrap(originals.first { $0.id == RuleCollectionIdentifier.macFunctionKeys })
        let functionKeys = try XCTUnwrap(loaded.first { $0.id == RuleCollectionIdentifier.macFunctionKeys })
        // The catalog's media definition emits consumer keys the driverless
        // session refuses, so a refilled entry must be plain F1-F12.
        XCTAssertEqual(functionKeys.functionKeyMode, .function)
        XCTAssertTrue(functionKeys.isEnabled)
        XCTAssertEqual(functionKeys.mappings.map(\.action),
                       RuleCollectionCatalog.functionKeyMappings(for: .function).map(\.action))
        XCTAssertNotEqual(original.functionKeyMode, .function, "The catalog default differs, so this test can fail")
        for collection in loaded where collection.id != kept.id && collection.id != original.id {
            XCTAssertFalse(collection.isEnabled, "\(collection.name) must not turn on for an existing profile")
        }
    }
}
