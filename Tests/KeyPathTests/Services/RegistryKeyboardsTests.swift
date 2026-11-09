@testable import KeyPathAppKit
import XCTest

final class RegistryKeyboardsTests: XCTestCase {
    func testKeyboardUsagePairMarksKeyboard() {
        // The Apple internal keyboard lists keyboard among several usages.
        XCTAssertTrue(RegistryKeyboards.isKeyboard(usages: [(1, 6), (12, 1), (65280, 6)], primary: (65280, 11)))
    }

    func testPrimaryUsageAloneMarksKeyboard() {
        XCTAssertTrue(RegistryKeyboards.isKeyboard(usages: [], primary: (1, 6)))
    }

    func testTrackpadAndConsumerDevicesAreNotKeyboards() {
        XCTAssertFalse(RegistryKeyboards.isKeyboard(usages: [(1, 2), (1, 1), (13, 5)], primary: (1, 2)))
        XCTAssertFalse(RegistryKeyboards.isKeyboard(usages: [(12, 1)], primary: (12, 1)))
    }

    @MainActor
    func testEventFilteringKeepsInternalKeyboardWithoutIDs() {
        let internalKeyboard = RegistryKeyboards.Entry(
            registryID: 1, vendorID: 0, productID: 0,
            productName: "Apple Internal Keyboard / Trackpad", keyboardType: nil
        )
        XCTAssertNotNil(HIDDeviceMonitor.event(from: internalKeyboard, isConnected: true))

        let anonymous = RegistryKeyboards.Entry(
            registryID: 2, vendorID: 0, productID: 0, productName: "Unknown Keyboard", keyboardType: nil
        )
        XCTAssertNil(HIDDeviceMonitor.event(from: anonymous, isConnected: true))

        let virtual = RegistryKeyboards.Entry(
            registryID: 3, vendorID: 0x16C0, productID: 0x27DB, productName: "Karabiner VirtualHIDKeyboard", keyboardType: nil
        )
        XCTAssertNil(HIDDeviceMonitor.event(from: virtual, isConnected: true))
    }

    func testRegistryEnumerationNeedsNoPermission() {
        // Reading the registry must not throw or prompt; on a Mac with a keyboard it finds one.
        _ = RegistryKeyboards.current()
    }
}
