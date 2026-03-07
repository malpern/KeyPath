@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class CLIFacadeTests: XCTestCase {
    private let facade = CLIFacade()

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
        // Ensure different UUIDs (makeCollections already does this)
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
        // "Vim" matches "Vim" exactly and is a substring of "Vim Extended"
        let collections = makeCollections(["Vim", "Vim Extended"])
        let index = try facade.resolveCollectionIndex(nameOrId: "Vim", in: collections)
        XCTAssertEqual(index, 0)
    }

    func testResolveUUIDTakesPriorityOverNameMatch() throws {
        let collections = makeCollections(["Home Row Mods", "Vim Layer"])
        // Use UUID of first collection as the search — should find index 0
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

    // MARK: - validateKey

    func testValidateKeyReturnsCanonicalForm() {
        XCTAssertEqual(facade.validateKey("caps"), "caps")
        XCTAssertEqual(facade.validateKey("Escape"), "esc")
        XCTAssertEqual(facade.validateKey("LALT"), "lalt")
    }

    func testValidateKeyReturnsNilForInvalid() {
        XCTAssertNil(facade.validateKey("blahblah"))
        XCTAssertNil(facade.validateKey("notakey123"))
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
