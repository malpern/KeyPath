@preconcurrency import XCTest

@testable import KeyPathAppKit

final class RuleCollectionStoreTests: XCTestCase {
    func testLoadFallsBackToDefaultsWhenFileMissing() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        let store = RuleCollectionStore.testStore(at: tempURL)

        let collections = await store.loadCollections()

        XCTAssertFalse(collections.isEmpty, "Default catalog should be returned when file missing")
        XCTAssertEqual(collections.first?.name, "macOS Function Keys")
    }

    func testSaveAndLoadRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let store = RuleCollectionStore.testStore(at: fileURL)

        let sample = [
            RuleCollection(
                name: "Custom",
                summary: "User rules",
                category: .custom,
                mappings: [
                    KeyMapping(input: "caps_lock", output: "escape"),
                    KeyMapping(input: "left_shift", output: "hyper")
                ],
                isEnabled: true,
                isSystemDefault: false,
                icon: "star"
            )
        ]

        try await store.saveCollections(sample)
        let loaded = await store.loadCollections()

        let loadedIDs = Set(loaded.map(\.id))
        let sampleIDs = Set(sample.map(\.id))
        let catalogIDs = Set(RuleCollectionCatalog().defaultCollections().map(\.id))

        XCTAssertTrue(
            loadedIDs.isSuperset(of: sampleIDs),
            "Persisted collections should remain present after load"
        )
        XCTAssertTrue(
            loadedIDs.isSuperset(of: catalogIDs),
            "Loaded collections should also include catalog defaults"
        )
    }

    func testLoadUpgradesBuiltInCollectionsWithLatestMetadata() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let legacyEntry: [String: Any] = [
            "id": RuleCollectionIdentifier.vimNavigation.uuidString,
            "name": "Vim Navigation",
            "summary": "Legacy",
            "category": RuleCollectionCategory.navigation.rawValue,
            "mappings": [
                ["id": UUID().uuidString, "input": "h", "output": "left"]
            ],
            "isEnabled": true,
            "isSystemDefault": false,
            "icon": "arrow"
        ]

        let data = try JSONSerialization.data(withJSONObject: [legacyEntry])
        try data.write(to: fileURL)

        let store = RuleCollectionStore.testStore(at: fileURL)
        let loaded = await store.loadCollections()

        let vim = loaded.first { $0.id == RuleCollectionIdentifier.vimNavigation }
        XCTAssertNotNil(vim)
        XCTAssertEqual(vim?.targetLayer, .navigation)
        XCTAssertEqual(vim?.momentaryActivator?.input, "space")
        XCTAssertEqual(vim?.momentaryActivator?.targetLayer, .navigation)
        XCTAssertEqual(vim?.activationHint, "Hold Leader key to enter Navigation layer")
    }

    func testLoadAddsMissingCatalogDefaultsWhenFileHasSubset() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rule-collections-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("collections.json")

        let catalog = RuleCollectionCatalog()
        guard let macOnly = catalog.defaultCollections().first(
            where: { $0.id == RuleCollectionIdentifier.macFunctionKeys }
        ) else {
            XCTFail("Missing macOS Function Keys in catalog")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode([macOnly])
        try data.write(to: fileURL)

        let store = RuleCollectionStore.testStore(at: fileURL)
        let loaded = await store.loadCollections()

        let loadedIDs = Set(loaded.map(\.id))
        let defaultIDs = Set(catalog.defaultCollections().map(\.id))

        XCTAssertEqual(
            defaultIDs, loadedIDs,
            "Loading should merge persisted subset with all catalog defaults (including new ones)"
        )
    }
}
