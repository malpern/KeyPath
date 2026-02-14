@testable import KeyPathAppKit
import XCTest

final class KanataMacOSDeviceExclusionParserTests: XCTestCase {
    #if os(macOS)
        func testParseExcludedMacOSDeviceNamesExtractsHashAndProductKey() {
            let output = """
            0xABCDEF01 1452 610 Apple Internal Keyboard / Trackpad
            0x1234ABCD 1452 611 VirtualHIDKeyboard

            0xDEADBEEF 1452 612 Karabiner-DriverKit-VirtualHIDDevice-VirtualHIDKeyboard
            """

            let parsed = KanataConfiguration.parseExcludedMacOSDeviceNames(fromKanataList: output)

            // Non-VirtualHID device should not appear.
            XCTAssertFalse(parsed.contains("0xABCDEF01"))

            // VirtualHID lines should contribute both the hash and the "product key" portion.
            XCTAssertTrue(parsed.contains("0x1234ABCD"))
            XCTAssertTrue(parsed.contains("VirtualHIDKeyboard"))

            XCTAssertTrue(parsed.contains("0xDEADBEEF"))
            XCTAssertTrue(parsed.contains("Karabiner-DriverKit-VirtualHIDDevice-VirtualHIDKeyboard"))

            // Deterministic ordering (sorted).
            XCTAssertEqual(parsed, parsed.sorted())
        }

        func testParseExcludedMacOSDeviceNamesDeduplicatesAndIgnoresNonMatchingLines() {
            let output = """
            nonsense
            0x11111111 1 2 VirtualHIDKeyboard
            0x11111111 1 2 VirtualHIDKeyboard
            0x22222222 3 4 Some Other Device
            """

            let parsed = KanataConfiguration.parseExcludedMacOSDeviceNames(fromKanataList: output)
            XCTAssertEqual(parsed, ["0x11111111", "VirtualHIDKeyboard"])
        }
    #endif
}
