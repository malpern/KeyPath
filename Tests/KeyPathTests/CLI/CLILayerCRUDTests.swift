@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class CLILayerCRUDTests: XCTestCase {
    private let facade = CollectionsFacade()
    private var originalCollections: [RuleCollection] = []

    override func setUp() async throws {
        try await super.setUp()
        originalCollections = await RuleCollectionStore.shared.loadCollections()
    }

    override func tearDown() async throws {
        try await RuleCollectionStore.shared.saveCollections(originalCollections)
        try await super.tearDown()
    }

    // MARK: - listDefinedLayers

    func testListDefinedLayersIncludesBase() async {
        let layers = await facade.listDefinedLayers()
        XCTAssertTrue(layers.contains("base"))
    }

    func testListDefinedLayersIncludesNewLayer() async throws {
        _ = try await facade.createLayer(name: "vim")
        let layers = await facade.listDefinedLayers()
        XCTAssertTrue(layers.contains("vim"))
    }

    // MARK: - createLayer

    func testLayerCreateCreatesCollection() async throws {
        let collection = try await facade.createLayer(name: "vim")
        XCTAssertEqual(collection.name, "vim Layer")
        XCTAssertTrue(collection.isEnabled)

        let collections = await RuleCollectionStore.shared.loadCollections()
        let created = collections.first(where: { $0.id.uuidString == collection.id })
        XCTAssertNotNil(created)
        XCTAssertEqual(created?.targetLayer.kanataName, "vim")
        XCTAssertEqual(created?.category, .layers)
    }

    // MARK: - deleteLayer

    func testLayerDeleteRemovesCollections() async throws {
        _ = try await facade.createLayer(name: "temp")
        let removed = try await facade.deleteLayer(name: "temp")
        XCTAssertEqual(removed, 1)

        let layers = await facade.listDefinedLayers()
        XCTAssertFalse(layers.contains("temp"))
    }

    func testLayerDeleteNonexistentReturnsZero() async throws {
        let removed = try await facade.deleteLayer(name: "nonexistent-layer-xyz")
        XCTAssertEqual(removed, 0)
    }

    // MARK: - renameLayer

    func testLayerRenameUpdatesCollections() async throws {
        _ = try await facade.createLayer(name: "oldlayer")
        let updated = try await facade.renameLayer(oldName: "oldlayer", newName: "newlayer")
        XCTAssertEqual(updated, 1)

        let layers = await facade.listDefinedLayers()
        XCTAssertTrue(layers.contains("newlayer"))
        XCTAssertFalse(layers.contains("oldlayer"))
    }

    func testLayerRenameNonexistentReturnsZero() async throws {
        let updated = try await facade.renameLayer(oldName: "nosuch", newName: "whatever")
        XCTAssertEqual(updated, 0)
    }
}
