@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class CollectionsFacadeTests: XCTestCase {
    private let facade = CollectionsFacade()

    // MARK: - resolveCollectionIndex

    func testResolveByExactUUID() throws {
        let collections = makeCollections(["Home Row Mods", "Vim Layer"])
        let index = try facade.resolveCollectionIndex(
            nameOrId: collections[1].id.uuidString,
            in: collections
        )
        XCTAssertEqual(index, 1)
    }

    func testResolveByExactNameCaseInsensitive() throws {
        let collections = makeCollections(["Home Row Mods", "Vim Layer"])
        let index = try facade.resolveCollectionIndex(nameOrId: "vim layer", in: collections)
        XCTAssertEqual(index, 1)
    }

    func testResolveBySubstringWhenUnambiguous() throws {
        let collections = makeCollections(["Home Row Mods", "Vim Layer"])
        let index = try facade.resolveCollectionIndex(nameOrId: "vim", in: collections)
        XCTAssertEqual(index, 1)
    }

    func testResolveReturnsNilWhenNotFound() throws {
        let collections = makeCollections(["Home Row Mods"])
        let index = try facade.resolveCollectionIndex(nameOrId: "nonexistent", in: collections)
        XCTAssertNil(index)
    }

    func testResolveThrowsOnAmbiguousSubstring() throws {
        let collections = makeCollections(["Home Row Mods", "Home Row Toggles"])
        XCTAssertThrowsError(
            try facade.resolveCollectionIndex(nameOrId: "home row", in: collections)
        ) { error in
            guard let ambiguous = error as? AmbiguousCollectionMatch else {
                XCTFail("Expected AmbiguousCollectionMatch, got \(error)")
                return
            }
            XCTAssertEqual(ambiguous.matches.count, 2)
            XCTAssertEqual(ambiguous.query, "home row")
        }
    }

    func testResolveThrowsOnDuplicateExactNames() throws {
        let collections = makeCollections(["Vim Layer", "Vim Layer"])
        XCTAssertNotEqual(collections[0].id, collections[1].id)

        XCTAssertThrowsError(
            try facade.resolveCollectionIndex(nameOrId: "Vim Layer", in: collections)
        ) { error in
            guard let ambiguous = error as? AmbiguousCollectionMatch else {
                XCTFail("Expected AmbiguousCollectionMatch, got \(error)")
                return
            }
            XCTAssertEqual(ambiguous.matches.count, 2)
            XCTAssertTrue(
                ambiguous.hint.contains("Use the ID"),
                "Exact-name duplicates should tell user to use the ID, not the name"
            )
        }
    }

    func testResolveExactNameTakesPriorityOverSubstring() throws {
        let collections = makeCollections(["Vim", "Vim Extended"])
        let index = try facade.resolveCollectionIndex(nameOrId: "Vim", in: collections)
        XCTAssertEqual(index, 0)
    }

    func testResolveUUIDTakesPriorityOverNameMatch() throws {
        let collections = makeCollections(["Home Row Mods", "Vim Layer"])
        let index = try facade.resolveCollectionIndex(
            nameOrId: collections[0].id.uuidString,
            in: collections
        )
        XCTAssertEqual(index, 0)
    }

    func testResolveEmptyCollections() throws {
        let index = try facade.resolveCollectionIndex(nameOrId: "anything", in: [])
        XCTAssertNil(index)
    }

    // MARK: - Helpers

    private func makeCollections(_ names: [String]) -> [RuleCollection] {
        names.map { name in
            RuleCollection(
                name: name,
                summary: "Test collection",
                category: .productivity,
                mappings: []
            )
        }
    }
}
