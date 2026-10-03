import KeyPathCore
import XCTest

final class SessionOutputStateTests: XCTestCase {
    private func event(_ usage: UInt32, _ value: UInt64, page: UInt32 = 7) -> KanataHostBridgePassthruOutputEvent {
        .init(value: value, usagePage: page, usage: usage)
    }

    func testPhysicalMapIncludesANSIISOJISKeypadAndAllModifierSides() {
        XCTAssertEqual(SessionKeyMap.keyCodeToUsage[12], 20)
        XCTAssertEqual(SessionKeyMap.keyCodeToUsage[10], 100)
        XCTAssertEqual(SessionKeyMap.keyCodeToUsage[93], 137)
        XCTAssertEqual(SessionKeyMap.keyCodeToUsage[76], 88)
        XCTAssertEqual(SessionKeyMap.keyCodeToUsage[90], 111)
        for usage: UInt32 in 224 ... 231 {
            XCTAssertNotNil(SessionKeyMap.keyCode(forUsage: usage))
            XCTAssertNotEqual(SessionKeyMap.deviceModifierFlag(for: usage), 0)
        }
        XCTAssertNil(SessionKeyMap.keyCodeToUsage[63]) // Fn is not a USB keyboard key.
        XCTAssertEqual(Set(SessionKeyMap.keyCodeToUsage.values).count, SessionKeyMap.keyCodeToUsage.count)
    }

    func testControlHoldThenLetterAndReleaseMatchesHomeRowModifierChord() throws {
        var state = SessionOutputState()
        let control = try state.translate(event(224, 1))
        XCTAssertEqual(control.keyCode, 59)
        XCTAssertEqual(control.flags, SessionKeyMap.modifierFlags(for: 224))
        let letter = try state.translate(event(4, 1))
        XCTAssertEqual(letter.keyCode, 0)
        XCTAssertEqual(letter.flags, control.flags)
        XCTAssertEqual(try state.translate(event(4, 0)).flags, control.flags)
        XCTAssertEqual(try state.translate(event(224, 0)).flags, 0)
        XCTAssertTrue(state.heldUsages.isEmpty)
    }

    func testOneSideReleasePreservesOtherSideModifier() throws {
        var state = SessionOutputState()
        _ = try state.translate(event(225, 1))
        _ = try state.translate(event(229, 1))
        let release = try state.translate(event(225, 0))
        XCTAssertEqual(release.flags, SessionKeyMap.modifierFlags(for: 229))
        XCTAssertEqual(state.releaseAll().last?.flags, 0)
    }

    func testRepeatsKeepPressLedgerAndCleanupReleasesOrdinaryKeysFirst() throws {
        var state = SessionOutputState()
        _ = try state.translate(event(224, 1))
        _ = try state.translate(event(4, 1))
        XCTAssertTrue(try state.translate(event(4, 2)).isRepeat)
        let releases = state.releaseAll()
        XCTAssertEqual(releases.map(\.keyCode), [0, 59])
        XCTAssertTrue(releases.allSatisfy { !$0.isDown && !$0.isRepeat })
        XCTAssertNotEqual(releases.first?.flags, 0)
        XCTAssertEqual(releases.last?.flags, 0)
        XCTAssertTrue(state.releaseAll().isEmpty)
    }

    func testUnknownOutputFailsWithoutChangingHeldLedger() throws {
        var state = SessionOutputState()
        _ = try state.translate(event(224, 1))
        for unsupported in [event(4, 3), event(0xFFFF, 1), event(4, 1, page: 12)] {
            XCTAssertThrowsError(try state.translate(unsupported))
            XCTAssertEqual(state.heldUsages, [224])
        }
        XCTAssertThrowsError(try state.translate(event(4, 2)))
        XCTAssertEqual(state.releaseAll().count, 1)
    }

    func testReportRejectsStaleForeignAndFutureEvidence() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let report = SessionRuntimeReport(
            nonce: "owned", pid: 100, uid: 501, state: .running,
            accessibility: true, effectiveInputAccess: true, tapActive: true,
            tcpPort: 37001, inputCount: 2, outputCount: 2, timestamp: now
        )
        XCTAssertTrue(report.isCurrent(nonce: "owned", pid: 100, uid: 501, now: now))
        XCTAssertFalse(report.isCurrent(nonce: "foreign", pid: 100, uid: 501, now: now))
        XCTAssertFalse(report.isCurrent(nonce: "owned", pid: 101, uid: 501, now: now))
        XCTAssertFalse(report.isCurrent(nonce: "owned", pid: 100, uid: 0, now: now))
        XCTAssertFalse(report.isCurrent(nonce: "owned", pid: 100, uid: 501, now: now.addingTimeInterval(3)))
        XCTAssertFalse(report.isCurrent(nonce: "owned", pid: 100, uid: 501, now: now.addingTimeInterval(-2)))
        XCTAssertEqual(try JSONDecoder().decode(SessionRuntimeReport.self, from: JSONEncoder().encode(report)), report)
    }
}
