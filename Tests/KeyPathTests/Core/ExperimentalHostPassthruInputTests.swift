@testable import KeyPathCore
import XCTest

final class ExperimentalHostPassthruInputTests: XCTestCase {
    func testMapsLetterAKeyDown() {
        let event = ExperimentalHostPassthruInputMapper.eventForKeyCode(0, isKeyDown: true)
        XCTAssertEqual(
            event,
            ExperimentalHostPassthruInputEvent(value: 1, usagePage: 0x07, usage: 0x04)
        )
    }

    func testMapsLeftShiftKeyUp() {
        let event = ExperimentalHostPassthruInputMapper.eventForKeyCode(56, isKeyDown: false)
        XCTAssertEqual(
            event,
            ExperimentalHostPassthruInputEvent(value: 0, usagePage: 0x07, usage: 0xE1)
        )
    }

    func testUnknownKeyCodeReturnsNil() {
        XCTAssertNil(ExperimentalHostPassthruInputMapper.eventForKeyCode(9999, isKeyDown: true))
    }
}
