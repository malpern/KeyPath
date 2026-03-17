@testable import KeyPathAppKit
import XCTest

final class DeviceLayoutBindingStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceLayoutBindingStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSaveAndLoadBinding() async throws {
        let fileURL = tempDir.appendingPathComponent("DeviceLayoutBindings.json")
        let store = DeviceLayoutBindingStore.testStore(at: fileURL)

        let binding = DeviceLayoutBindingStore.Binding(
            vendorProductKey: "4653:0001",
            layoutId: "sofle",
            keyboardName: "Sofle",
            acceptedAt: Date()
        )

        try await store.saveBinding(binding)
        let loaded = await store.binding(vendorID: 0x4653, productID: 0x0001)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.layoutId, "sofle")
        XCTAssertEqual(loaded?.keyboardName, "Sofle")
    }

    func testRemoveBinding() async throws {
        let fileURL = tempDir.appendingPathComponent("DeviceLayoutBindings.json")
        let store = DeviceLayoutBindingStore.testStore(at: fileURL)

        let binding = DeviceLayoutBindingStore.Binding(
            vendorProductKey: "4653:0001",
            layoutId: "sofle",
            keyboardName: "Sofle",
            acceptedAt: Date()
        )

        try await store.saveBinding(binding)
        try await store.removeBinding(vendorID: 0x4653, productID: 0x0001)
        let loaded = await store.binding(vendorID: 0x4653, productID: 0x0001)

        XCTAssertNil(loaded)
    }

    func testOverwriteExistingBinding() async throws {
        let fileURL = tempDir.appendingPathComponent("DeviceLayoutBindings.json")
        let store = DeviceLayoutBindingStore.testStore(at: fileURL)

        let binding1 = DeviceLayoutBindingStore.Binding(
            vendorProductKey: "4653:0001",
            layoutId: "sofle",
            keyboardName: "Sofle",
            acceptedAt: Date()
        )

        let binding2 = DeviceLayoutBindingStore.Binding(
            vendorProductKey: "4653:0001",
            layoutId: "custom-abc",
            keyboardName: "Sofle Custom",
            acceptedAt: Date()
        )

        try await store.saveBinding(binding1)
        try await store.saveBinding(binding2)

        let all = await store.allBindings()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.layoutId, "custom-abc")
    }

    func testMultipleDeviceBindings() async throws {
        let fileURL = tempDir.appendingPathComponent("DeviceLayoutBindings.json")
        let store = DeviceLayoutBindingStore.testStore(at: fileURL)

        let binding1 = DeviceLayoutBindingStore.Binding(
            vendorProductKey: "4653:0001",
            layoutId: "sofle",
            keyboardName: "Sofle",
            acceptedAt: Date()
        )

        let binding2 = DeviceLayoutBindingStore.Binding(
            vendorProductKey: "CB10:1256",
            layoutId: "corne",
            keyboardName: "Corne",
            acceptedAt: Date()
        )

        try await store.saveBinding(binding1)
        try await store.saveBinding(binding2)

        let all = await store.allBindings()
        XCTAssertEqual(all.count, 2)

        let sofle = await store.binding(vendorID: 0x4653, productID: 0x0001)
        XCTAssertEqual(sofle?.layoutId, "sofle")

        let corne = await store.binding(vendorID: 0xCB10, productID: 0x1256)
        XCTAssertEqual(corne?.layoutId, "corne")
    }

    func testEmptyStoreReturnsNil() async {
        let fileURL = tempDir.appendingPathComponent("DeviceLayoutBindings.json")
        let store = DeviceLayoutBindingStore.testStore(at: fileURL)

        let loaded = await store.binding(vendorID: 0x4653, productID: 0x0001)
        XCTAssertNil(loaded)
    }

    func testFilePersistence() async throws {
        let fileURL = tempDir.appendingPathComponent("DeviceLayoutBindings.json")

        // Save with one store instance
        let store1 = DeviceLayoutBindingStore.testStore(at: fileURL)
        let binding = DeviceLayoutBindingStore.Binding(
            vendorProductKey: "4653:0001",
            layoutId: "sofle",
            keyboardName: "Sofle",
            acceptedAt: Date()
        )
        try await store1.saveBinding(binding)

        // Load with a fresh store instance
        let store2 = DeviceLayoutBindingStore.testStore(at: fileURL)
        let loaded = await store2.binding(vendorID: 0x4653, productID: 0x0001)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.layoutId, "sofle")
    }
}
