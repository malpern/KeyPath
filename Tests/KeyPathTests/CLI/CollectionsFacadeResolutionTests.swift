@testable import KeyPathAppKit
import XCTest

final class CollectionsFacadeResolutionTests: XCTestCase {

    private let facade = CollectionsFacade()

    private func testCollections() -> [RuleCollection] {
        [
            RuleCollection(
                id: UUID(),
                name: "Caps Lock Remap",
                summary: "Remap caps",
                category: .custom,
                mappings: [],
                isEnabled: true,
                icon: "star",
                tags: [],
                targetLayer: .base,
                configuration: .list
            ),
            RuleCollection(
                id: UUID(),
                name: "Home Row Mods",
                summary: "HRM",
                category: .custom,
                mappings: [],
                isEnabled: false,
                icon: "star",
                tags: [],
                targetLayer: .base,
                configuration: .list
            ),
            RuleCollection(
                id: UUID(),
                name: "Vim Navigation",
                summary: "Vim nav",
                category: .custom,
                mappings: [],
                isEnabled: true,
                icon: "star",
                tags: [],
                targetLayer: .navigation,
                configuration: .list
            ),
        ]
    }

    // MARK: - resolveCollectionIndex: by UUID

    func testResolveByUUID_ReturnsCorrectIndex() throws {
        let collections = testCollections()
        let id = collections[1].id.uuidString
        let index = try facade.resolveCollectionIndex(nameOrId: id, in: collections)
        XCTAssertEqual(index, 1)
    }

    func testResolveByUUID_UnknownReturnsNil() throws {
        let index = try facade.resolveCollectionIndex(nameOrId: UUID().uuidString, in: testCollections())
        XCTAssertNil(index)
    }

    // MARK: - resolveCollectionIndex: by exact name

    func testResolveByExactName_CaseInsensitive() throws {
        let index = try facade.resolveCollectionIndex(nameOrId: "caps lock remap", in: testCollections())
        XCTAssertEqual(index, 0)
    }

    func testResolveByExactName_ExactMatch() throws {
        let index = try facade.resolveCollectionIndex(nameOrId: "Home Row Mods", in: testCollections())
        XCTAssertEqual(index, 1)
    }

    // MARK: - resolveCollectionIndex: by substring

    func testResolveBySubstring_UniqueMatch() throws {
        let index = try facade.resolveCollectionIndex(nameOrId: "Vim", in: testCollections())
        XCTAssertEqual(index, 2)
    }

    func testResolveBySubstring_AmbiguousThrows() {
        // "o" appears in both "Home Row Mods" and "Caps Lock Remap"
        XCTAssertThrowsError(try facade.resolveCollectionIndex(nameOrId: "o", in: testCollections())) { error in
            XCTAssertTrue(error is AmbiguousCollectionMatch)
        }
    }

    func testResolveBySubstring_NoMatch_ReturnsNil() throws {
        let index = try facade.resolveCollectionIndex(nameOrId: "ZZZZZ", in: testCollections())
        XCTAssertNil(index)
    }

    // MARK: - parseLayer

    func testParseLayer_Base() {
        let layer = CollectionsFacade.parseLayer("base")
        XCTAssertEqual(layer, .base)
    }

    func testParseLayer_Nav() {
        let layer = CollectionsFacade.parseLayer("nav")
        XCTAssertEqual(layer, .navigation)
    }

    func testParseLayer_Navigation() {
        let layer = CollectionsFacade.parseLayer("navigation")
        XCTAssertEqual(layer, .navigation)
    }

    func testParseLayer_Custom() {
        let layer = CollectionsFacade.parseLayer("my-layer")
        XCTAssertEqual(layer, .custom("my-layer"))
    }

    func testParseLayer_CaseInsensitive() {
        XCTAssertEqual(CollectionsFacade.parseLayer("BASE"), .base)
        XCTAssertEqual(CollectionsFacade.parseLayer("Nav"), .navigation)
    }

    // MARK: - CLIRuleCollection

    func testCLIRuleCollection_FromRuleCollection() {
        let collection = RuleCollection(
            id: UUID(),
            name: "Test",
            summary: "A test",
            category: .custom,
            mappings: [
                KeyMapping(input: "a", action: .keystroke(key: "b"), description: ""),
                KeyMapping(input: "c", action: .keystroke(key: "d"), description: ""),
            ],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .base,
            configuration: .list
        )

        let cli = CLIRuleCollection(from: collection)
        XCTAssertEqual(cli.id, collection.id.uuidString)
        XCTAssertEqual(cli.name, "Test")
        XCTAssertTrue(cli.isEnabled)
        XCTAssertEqual(cli.mappingCount, 2)
        XCTAssertEqual(cli.summary, "A test")
    }

    // MARK: - CLIExportedCollection round-trip

    func testCLIExportedCollection_RoundTrip() {
        let collection = RuleCollection(
            id: UUID(),
            name: "Exported",
            summary: "For export",
            category: .custom,
            mappings: [
                KeyMapping(input: "x", action: .keystroke(key: "y"), description: "test"),
            ],
            isEnabled: true,
            icon: "star",
            tags: [],
            targetLayer: .navigation,
            configuration: .list
        )

        let exported = CLIExportedCollection(from: collection)
        XCTAssertEqual(exported.name, "Exported")
        XCTAssertEqual(exported.targetLayer, "nav")
        XCTAssertEqual(exported.mappings.count, 1)

        let restored = exported.toRuleCollection()
        XCTAssertEqual(restored.name, "Exported")
        XCTAssertEqual(restored.targetLayer, .navigation)
        XCTAssertEqual(restored.mappings.count, 1)
        XCTAssertEqual(restored.mappings[0].input, "x")
    }

    func testCLIExportedCollection_BaseLayer() {
        let collection = RuleCollection(
            name: "Base",
            summary: "",
            category: .custom,
            mappings: [],
            targetLayer: .base
        )
        let exported = CLIExportedCollection(from: collection)
        XCTAssertEqual(exported.targetLayer, "base")
        XCTAssertEqual(exported.toRuleCollection().targetLayer, .base)
    }

    func testCLIExportedCollection_CustomLayer() {
        let collection = RuleCollection(
            name: "My Layer",
            summary: "",
            category: .custom,
            mappings: [],
            targetLayer: .custom("my-layer")
        )
        let exported = CLIExportedCollection(from: collection)
        let restored = exported.toRuleCollection()
        XCTAssertEqual(restored.targetLayer, .custom("my-layer"))
    }

    // MARK: - CLIExportedMapping round-trip

    func testCLIExportedMapping_RoundTrip() {
        let mapping = KeyMapping(
            input: "caps",
            action: .keystroke(key: "esc"),
            shiftedOutput: "caps",
            behavior: .dualRole(DualRoleBehavior.homeRowMod(letter: "a", modifier: "lctl"))
        )

        let exported = CLIExportedMapping(from: mapping)
        let restored = exported.toKeyMapping()

        XCTAssertEqual(restored.input, "caps")
        XCTAssertEqual(restored.action, .keystroke(key: "esc"))
        XCTAssertEqual(restored.shiftedOutput, "caps")
        XCTAssertNotNil(restored.behavior)
    }

    // MARK: - AmbiguousCollectionMatch

    func testAmbiguousCollectionMatch_Description() {
        let err = AmbiguousCollectionMatch(
            query: "Mods",
            matches: [
                .init(name: "Home Row Mods", id: "aaa"),
                .init(name: "Chord Mods", id: "bbb")
            ]
        )
        XCTAssertTrue(err.description.contains("2 collections"))
        XCTAssertTrue(err.description.contains("Home Row Mods"))
    }

    // MARK: - CLIConflictStrategy

    func testCLIConflictStrategy_AllCasesExist() {
        let strategies: [CLIConflictStrategy] = [.fail, .skip, .replace, .merge]
        XCTAssertEqual(strategies.count, 4)
    }
}
