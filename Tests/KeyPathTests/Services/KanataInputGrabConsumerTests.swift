@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

/// Tests for parsing kanata's authoritative `InputGrab` TCP status (#630).
@MainActor
final class KanataInputGrabConsumerTests: KeyPathTestCase {
    // MARK: - parseInputGrab

    func testParseInputGrab_active_withDevices() {
        let body: [String: Any] = [
            "active": true,
            "devices": ["Apple Internal Keyboard / Trackpad", "HHKB-Hybrid"]
        ]
        let status = KanataEventListener.parseInputGrab(from: body, observedAt: Date())
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.active, true)
        XCTAssertEqual(status?.devices, ["Apple Internal Keyboard / Trackpad", "HHKB-Hybrid"])
        XCTAssertNil(status?.reason)
    }

    func testParseInputGrab_inactive_withReason() {
        let body: [String: Any] = [
            "active": false,
            "devices": [String](),
            "reason": "another process has exclusive grab"
        ]
        let status = KanataEventListener.parseInputGrab(from: body, observedAt: Date())
        XCTAssertEqual(status?.active, false)
        XCTAssertEqual(status?.devices, [])
        XCTAssertEqual(status?.reason, "another process has exclusive grab")
    }

    func testParseInputGrab_inactive_noReason_defaultsEmptyDevices() {
        let body: [String: Any] = ["active": false]
        let status = KanataEventListener.parseInputGrab(from: body, observedAt: Date())
        XCTAssertEqual(status?.active, false)
        XCTAssertEqual(status?.devices, [])
        XCTAssertNil(status?.reason)
    }

    func testParseInputGrab_missingActive_returnsNil() {
        let body: [String: Any] = ["devices": ["a"]]
        XCTAssertNil(KanataEventListener.parseInputGrab(from: body, observedAt: Date()))
    }
}
