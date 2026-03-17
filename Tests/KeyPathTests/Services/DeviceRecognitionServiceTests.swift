@testable import KeyPathAppKit
import XCTest

final class DeviceRecognitionServiceTests: XCTestCase {
    override func setUp() {
        QMKVIDPIDIndex.resetCache()
    }

    override func tearDown() {
        QMKVIDPIDIndex.resetCache()
    }

    func testRecognizeBuiltInKeyboard() async {
        // Seed the VID:PID index with a crkbd entry
        QMKVIDPIDIndex.seededEntries = [
            "CB10:1256": ["crkbd/rev4_0/standard"],
        ]

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0xCB10,
            productID: 0x1256,
            productName: "Corne Keyboard",
            isConnected: true
        )

        let service = DeviceRecognitionService()
        let result = await service.recognize(event: event)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isBuiltIn ?? false)
        XCTAssertEqual(result?.layoutId, "corne")
        XCTAssertEqual(result?.qmkPath, "crkbd/rev4_0/standard")
        XCTAssertFalse(result?.needsImport ?? true)
    }

    func testRecognizeNonBuiltInKeyboard() async {
        QMKVIDPIDIndex.seededEntries = [
            "1209:A1E5": ["atreus"],
        ]

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x1209,
            productID: 0xA1E5,
            productName: "Atreus",
            isConnected: true
        )

        let service = DeviceRecognitionService()
        let result = await service.recognize(event: event)

        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isBuiltIn ?? true)
        XCTAssertNil(result?.layoutId)
        XCTAssertTrue(result?.needsImport ?? false)
        XCTAssertEqual(result?.qmkPath, "atreus")
    }

    func testNoMatchReturnsNil() async {
        QMKVIDPIDIndex.seededEntries = [:]

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x05AC,
            productID: 0x0342,
            productName: "Apple Internal Keyboard",
            isConnected: true
        )

        let service = DeviceRecognitionService()
        let result = await service.recognize(event: event)

        XCTAssertNil(result)
    }

    func testRankingPrefersBuiltIn() async {
        // Multiple paths, one has a built-in layout
        QMKVIDPIDIndex.seededEntries = [
            "CB10:1256": ["crkbd/rev4_0/standard", "crkbd/rev1"],
        ]

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0xCB10,
            productID: 0x1256,
            productName: "Corne",
            isConnected: true
        )

        let service = DeviceRecognitionService()
        let result = await service.recognize(event: event)

        // Both paths map to built-in "corne", but shorter path wins among equals
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isBuiltIn ?? false)
        XCTAssertEqual(result?.layoutId, "corne")
    }
}
