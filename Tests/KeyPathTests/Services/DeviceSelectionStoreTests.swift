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
        // Reset shared cache to avoid polluting other tests
        DeviceSelectionCache.shared.reset()
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
        let cache = DeviceSelectionCache()
        let store = DeviceSelectionStore.testStore(at: fileURL, cache: cache)

        let selections = [
            DeviceSelection(hash: "0xTEST", productKey: "Test", isEnabled: false, lastSeen: Date()),
        ]

        try await store.saveSelections(selections)

        XCTAssertFalse(cache.isEnabled(hash: "0xTEST"))
        XCTAssertTrue(DeviceSelectionCache.shared.isEnabled(hash: "0xTEST"))
    }

    func testCacheConnectedDevicesRoundTrip() {
        let cache = DeviceSelectionCache()
        XCTAssertTrue(cache.getConnectedDevices().isEmpty)

        let devices = [
            ConnectedDevice(hash: "0x1", vendorID: 1, productID: 2, productKey: "KB", isVirtualHID: false),
        ]
        cache.updateConnectedDevices(devices)
        XCTAssertEqual(cache.getConnectedDevices().count, 1)
        XCTAssertEqual(cache.getConnectedDevices().first?.hash, "0x1")
    }

    func testCacheResetClearsAll() {
        let cache = DeviceSelectionCache()
        cache.update([DeviceSelection(hash: "0xAA", productKey: "A", isEnabled: false, lastSeen: Date())])
        cache.updateConnectedDevices([ConnectedDevice(hash: "0x1", vendorID: 1, productID: 2, productKey: "KB", isVirtualHID: false)])

        cache.reset()

        XCTAssertTrue(cache.isEnabled(hash: "0xAA")) // Defaults to true after reset
        XCTAssertTrue(cache.getConnectedDevices().isEmpty)
    }

    func testDeviceSelectionDisplayName() {
        let selection = DeviceSelection(
            hash: "0x1",
            productKey: "Apple Internal Keyboard / Trackpad",
            isEnabled: true,
            lastSeen: Date()
        )
        XCTAssertEqual(selection.displayName, "Apple Internal Keyboard")
    }

    func testPrimeSharedCacheFromDiskLoadsSelections() async throws {
        let fileURL = tempDir.appendingPathComponent("DeviceSelection.json")
        let store = DeviceSelectionStore.testStore(at: fileURL)
        let selections = [
            DeviceSelection(hash: "0xSYNC", productKey: "Sync", isEnabled: false, lastSeen: Date()),
        ]

        try await store.saveSelections(selections)
        DeviceSelectionCache.shared.reset()

        DeviceSelectionStore.primeSharedCacheFromDisk(fileURL: fileURL)

        XCTAssertFalse(DeviceSelectionCache.shared.isEnabled(hash: "0xSYNC"))
    }
}
