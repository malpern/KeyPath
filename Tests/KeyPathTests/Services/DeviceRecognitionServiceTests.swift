@testable import KeyPathAppKit
import XCTest

final class DeviceRecognitionServiceTests: KeyPathTestCase {
    override func setUp() {
        super.setUp()
        KeyboardDetectionIndex.resetCache()
    }

    override func tearDown() {
        KeyboardDetectionIndex.resetCache()
        super.tearDown()
    }

    func testRecognizeBuiltInKeyboardFromVIAExactMatch() async {
        KeyboardDetectionIndex.seedIndex(exactEntries: [
            .init(
                matchKey: "CB10:1256",
                matchType: .exactVIDPID,
                source: .via,
                confidence: .high,
                displayName: "Corne Keyboard",
                manufacturer: nil,
                qmkPath: "crkbd/rev4_0/standard",
                builtInLayoutId: "corne"
            )
        ])

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
        XCTAssertEqual(result?.source, .via)
    }

    func testRecognizeNonBuiltInKeyboardFallsBackToQMK() async {
        KeyboardDetectionIndex.seedIndex(exactEntries: [
            .init(
                matchKey: "1209:A1E5",
                matchType: .exactVIDPID,
                source: .qmk,
                confidence: .high,
                displayName: "Atreus",
                manufacturer: nil,
                qmkPath: "atreus",
                builtInLayoutId: nil
            )
        ])

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
        XCTAssertEqual(result?.source, .qmk)
    }

    func testNoMatchReturnsNil() async {
        KeyboardDetectionIndex.seedIndex(exactEntries: [])

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x1337,
            productID: 0xBEEF,
            productName: "Mystery Board",
            isConnected: true
        )

        let service = DeviceRecognitionService()
        let result = await service.recognize(event: event)

        XCTAssertNil(result)
    }

    func testRecognizeAppleInternalKeyboardAsBuiltInMacBook() async {
        KeyboardDetectionIndex.seedIndex(exactEntries: [])

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x05AC,
            productID: 0x0342,
            productName: "Apple Internal Keyboard / Trackpad",
            isConnected: true
        )

        let service = DeviceRecognitionService()
        let result = await service.recognize(event: event)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.keyboardName, "MacBook Keyboard")
        XCTAssertEqual(result?.manufacturer, "Apple")
        XCTAssertTrue(result?.isBuiltIn ?? false)
        XCTAssertFalse(result?.needsImport ?? true)
        XCTAssertNotNil(result?.layoutId)
        XCTAssertEqual(result?.source, .override)
    }

    func testRecognizeZeroIdentityAppleInternalKeyboardAsBuiltInMacBook() async {
        KeyboardDetectionIndex.seedIndex(exactEntries: [])

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x0000,
            productID: 0x0000,
            productName: "Apple Internal Keyboard / Trackpad",
            isConnected: true
        )

        let service = DeviceRecognitionService()
        let result = await service.recognize(event: event)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.keyboardName, "MacBook Keyboard")
        XCTAssertTrue(result?.isBuiltIn ?? false)
        XCTAssertFalse(result?.needsImport ?? true)
    }

    func testRecognizeAppleMagicKeyboardWithNumericKeypad() async {
        KeyboardDetectionIndex.seedIndex(exactEntries: [])

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x05AC,
            productID: 0x026C,
            productName: "Magic Keyboard with Numeric Keypad",
            isConnected: true
        )

        let service = DeviceRecognitionService()
        let result = await service.recognize(event: event)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.keyboardName, "Magic Keyboard with Numeric Keypad")
        XCTAssertEqual(result?.layoutId, "magic-keyboard-numpad")
        XCTAssertTrue(result?.isBuiltIn ?? false)
        XCTAssertEqual(result?.source, .override)
    }

    func testVendorFallbackStillWorksWhenItCollapsesToSingleBuiltInLayout() async {
        KeyboardDetectionIndex.seedIndex(
            exactEntries: [],
            vendorFallbackEntries: [
                .init(
                    matchKey: "4653",
                    matchType: .vendorOnly,
                    source: .qmk,
                    confidence: .low,
                    displayName: "Sofle",
                    manufacturer: nil,
                    qmkPath: "sofle",
                    builtInLayoutId: "sofle"
                )
            ]
        )

        let event = HIDDeviceMonitor.HIDKeyboardEvent(
            vendorID: 0x4653,
            productID: 0x9999,
            productName: "Mystery Sofle",
            isConnected: true
        )

        let service = DeviceRecognitionService()
        let result = await service.recognize(event: event)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isBuiltIn ?? false)
        XCTAssertEqual(result?.layoutId, "sofle")
        XCTAssertEqual(result?.matchType, .vendorOnly)
    }
}
