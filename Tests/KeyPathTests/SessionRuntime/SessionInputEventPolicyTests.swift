import CoreGraphics
@testable import KeyPathAppKit
import XCTest

final class SessionInputEventPolicyTests: XCTestCase {
    func testSoftwarePastePreservesAggregateCommandOnBothEdges() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        for down in [true, false] {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down))
            event.flags = .maskCommand
            XCTAssertGreaterThan(event.getIntegerValueField(.eventSourceUnixProcessID), 0)
            // No left/right Command device bits or preceding flagsChanged event.
            XCTAssertEqual(event.flags.rawValue & 0xFFFF, 0)
            XCTAssertTrue(SessionInputEventPolicy.isSoftwareKeyboardEvent(type: event.type, event: event))
            XCTAssertEqual(event.flags, .maskCommand)
        }
    }

    func testSoftwareModifierAndUnicodeEventsBypassPhysicalState() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 1234)
        XCTAssertTrue(SessionInputEventPolicy.isSoftwareKeyboardEvent(type: .flagsChanged, event: event))
        event.flags = []
        var text: [UniChar] = [0x0061, 0x0062]
        event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: &text)
        XCTAssertTrue(SessionInputEventPolicy.isSoftwareKeyboardEvent(type: .keyDown, event: event))
        XCTAssertTrue(SessionInputEventPolicy.isSoftwareKeyboardEvent(type: .keyUp, event: event))
    }

    func testHardwareEventsStillReachRemapper() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.flags = .maskCommand
        for type: CGEventType in [.keyDown, .keyUp, .flagsChanged] {
            XCTAssertFalse(SessionInputEventPolicy.isSoftwareKeyboardEvent(type: type, event: event))
        }
    }

    func testTapDisabledNotificationsStillReachRecovery() throws {
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 1234)
        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            XCTAssertFalse(SessionInputEventPolicy.isSoftwareKeyboardEvent(type: type, event: event))
        }
    }
}
