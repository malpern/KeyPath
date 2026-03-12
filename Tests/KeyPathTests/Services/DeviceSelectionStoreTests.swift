@testable import KeyPathAppKit
import XCTest

final class DeviceSelectionStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceSelectionStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSaveAndLoadRoundTrip() async throws {
        let fileURL = tempDir.appendingPathComponent("DeviceSelection.json")
        let store = DeviceSelectionStore.testStore(at: fileURL)

        let selections = [
            DeviceSelection(hash: "0xAA", productKey: "Keyboard A", isEnabled: true, lastSeen: Date()),
            DeviceSelection(hash: "0xBB", productKey: "Keyboard B", isEnabled: false, lastSeen: Date()),
        ]

        try await store.saveSelections(selections)
        let loaded = await store.loadSelections()

        XCTAssertEqual(loaded.count, 2)

        let a = loaded.first { $0.hash == "0xAA" }
        XCTAssertNotNil(a)
        XCTAssertTrue(a?.isEnabled ?? false)

        let b = loaded.first { $0.hash == "0xBB" }
        XCTAssertNotNil(b)
        XCTAssertFalse(b?.isEnabled ?? true)
    }

    func testLoadReturnsEmptyWhenFileDoesNotExist() async {
        let fileURL = tempDir.appendingPathComponent("nonexistent.json")
        let store = DeviceSelectionStore.testStore(at: fileURL)

        let loaded = await store.loadSelections()
        XCTAssertEqual(loaded.count, 0)
    }

    func testCacheDefaultsToEnabled() {
        let cache = DeviceSelectionCache()
        // Unknown hash should default to enabled
        XCTAssertTrue(cache.isEnabled(hash: "0xUNKNOWN"))
    }

    func testCacheReflectsUpdates() {
        let cache = DeviceSelectionCache()
        let selections = [
            DeviceSelection(hash: "0xAA", productKey: "A", isEnabled: true, lastSeen: Date()),
            DeviceSelection(hash: "0xBB", productKey: "B", isEnabled: false, lastSeen: Date()),
        ]
        cache.update(selections)

        XCTAssertTrue(cache.isEnabled(hash: "0xAA"))
        XCTAssertFalse(cache.isEnabled(hash: "0xBB"))
        // Unknown still defaults to enabled
        XCTAssertTrue(cache.isEnabled(hash: "0xCC"))
    }

    func testSaveSyncsToSharedCache() async throws {
        let fileURL = tempDir.appendingPathComponent("DeviceSelection.json")
        let store = DeviceSelectionStore.testStore(at: fileURL)

        let selections = [
            DeviceSelection(hash: "0xTEST", productKey: "Test", isEnabled: false, lastSeen: Date()),
        ]

        try await store.saveSelections(selections)

        // The shared cache should reflect the saved state
        XCTAssertFalse(DeviceSelectionCache.shared.isEnabled(hash: "0xTEST"))
    }
}
