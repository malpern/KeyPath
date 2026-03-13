@testable import KeyPathAppKit
import XCTest

final class DeviceEnumerationServiceTests: XCTestCase {
    func testParseAllDevicesExtractsAllFields() {
        let output = """
        0xABCDEF01 1452 610 Apple Internal Keyboard / Trackpad
        0x1234ABCD 1452 611 VirtualHIDKeyboard
        0xDEADBEEF 10684 65 Kinesis Advantage360 Pro
        """

        let devices = DeviceEnumerationService.parseAllDevices(fromKanataList: output)

        XCTAssertEqual(devices.count, 3)

        let apple = devices.first { $0.hash == "0xABCDEF01" }
        XCTAssertNotNil(apple)
        XCTAssertEqual(apple?.vendorID, 1452)
        XCTAssertEqual(apple?.productID, 610)
        XCTAssertEqual(apple?.productKey, "Apple Internal Keyboard / Trackpad")
        XCTAssertFalse(apple?.isVirtualHID ?? true)

        let virtual = devices.first { $0.hash == "0x1234ABCD" }
        XCTAssertNotNil(virtual)
        XCTAssertTrue(virtual?.isVirtualHID ?? false)

        let kinesis = devices.first { $0.hash == "0xDEADBEEF" }
        XCTAssertNotNil(kinesis)
        XCTAssertEqual(kinesis?.vendorID, 10684)
        XCTAssertEqual(kinesis?.productID, 65)
        XCTAssertFalse(kinesis?.isVirtualHID ?? true)
    }

    func testParseAllDevicesDetectsVirtualHIDVariants() {
        let output = """
        0x11111111 1 2 VirtualHIDKeyboard
        0x22222222 3 4 Karabiner-DriverKit-VirtualHIDDevice-VirtualHIDKeyboard
        0x33333333 5 6 Regular Keyboard
        """

        let devices = DeviceEnumerationService.parseAllDevices(fromKanataList: output)

        XCTAssertEqual(devices.count, 3)
        XCTAssertTrue(devices[0].isVirtualHID)
        XCTAssertTrue(devices[1].isVirtualHID)
        XCTAssertFalse(devices[2].isVirtualHID)
    }

    func testParseAllDevicesHandlesEmptyOutput() {
        XCTAssertEqual(DeviceEnumerationService.parseAllDevices(fromKanataList: ""), [])
    }

    func testParseAllDevicesHandlesMalformedLines() {
        let output = """
        nonsense line
        incomplete 1 2
        0xAA00BB11 100 200 Good Device
        another bad line
        """

        let devices = DeviceEnumerationService.parseAllDevices(fromKanataList: output)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.hash, "0xAA00BB11")
        XCTAssertEqual(devices.first?.productKey, "Good Device")
    }

    func testParseAllDevicesDeduplicatesByHash() {
        let output = """
        0x11111111 1 2 Device A
        0x11111111 1 2 Device A
        0x22222222 3 4 Device B
        """

        let devices = DeviceEnumerationService.parseAllDevices(fromKanataList: output)
        XCTAssertEqual(devices.count, 2)
    }

    func testDisplayNameCleansUpProductKey() {
        let device = ConnectedDevice(
            hash: "0x1",
            vendorID: 1452,
            productID: 610,
            productKey: "Apple Internal Keyboard / Trackpad",
            isVirtualHID: false
        )
        XCTAssertEqual(device.displayName, "Apple Internal Keyboard")
    }

    func testVendorProductHexFormatting() {
        let device = ConnectedDevice(
            hash: "0x1",
            vendorID: 1452,
            productID: 834,
            productKey: "Test",
            isVirtualHID: false
        )
        XCTAssertEqual(device.vendorProductHex, "05ac:0342")
    }
}
