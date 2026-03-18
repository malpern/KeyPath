@testable import KeyPathAppKit
import XCTest

final class KeyboardDisplayContextStoreTests: KeyPathTestCase {
    func testSaveLoadAndRemoveContext() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("KeyboardDisplayContexts.json")
        let store = KeyboardDisplayContextStore.testStore(at: tempURL)

        let context = KeyboardDisplayContextStore.Context(
            vendorProductKey: "29EA:1001",
            layoutId: "kinesis-mwave",
            keymapId: "graphite",
            includePunctuationStore: "{\"graphite\":true}",
            keyboardName: "Kinesis mWave",
            updatedAt: Date()
        )

        try await store.saveContext(context)

        let loaded = await store.context(vendorProductKey: "29EA:1001")
        XCTAssertEqual(loaded?.layoutId, "kinesis-mwave")
        XCTAssertEqual(loaded?.keymapId, "graphite")
        XCTAssertEqual(loaded?.includePunctuationStore, "{\"graphite\":true}")

        try await store.removeContext(vendorProductKey: "29EA:1001")
        let removed = await store.context(vendorProductKey: "29EA:1001")
        XCTAssertNil(removed)
    }
}
