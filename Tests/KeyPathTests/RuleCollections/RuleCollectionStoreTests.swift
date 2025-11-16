import XCTest
@testable import KeyPath

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

        XCTAssertEqual(loaded, sample)
    }
}
