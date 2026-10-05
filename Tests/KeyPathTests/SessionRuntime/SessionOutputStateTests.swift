import KeyPathCore
import XCTest

final class SessionOutputStateTests: XCTestCase {
    func testFunctionKeyFlagDoesNotBecomePhysicalFnOnRemappedLetter() {
        var state = SessionPhysicalModifierState()
        let function: UInt64 = 1 << 23
        let caps: UInt64 = 1 << 16
        XCTAssertEqual(state.passthroughFlags(keyCode: 79, isFlagsChanged: false, flags: function), 0)
        XCTAssertEqual(state.passthroughFlags(keyCode: 0, isFlagsChanged: false, flags: caps), caps)
        XCTAssertEqual(state.passthroughFlags(keyCode: 63, isFlagsChanged: true, flags: function), function)
        XCTAssertEqual(state.passthroughFlags(keyCode: 79, isFlagsChanged: false, flags: function), function)
        XCTAssertEqual(state.passthroughFlags(keyCode: 0, isFlagsChanged: false, flags: function), function)
        XCTAssertEqual(state.passthroughFlags(keyCode: 63, isFlagsChanged: true, flags: 0), 0)
        XCTAssertEqual(state.passthroughFlags(keyCode: 79, isFlagsChanged: false, flags: function), 0)
    }

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

    func testCapsOutputCannotEnterOrDisturbOwnedReleaseLedger() throws {
        var state = SessionOutputState()
        _ = try state.translate(event(224, 1))
        _ = try state.translate(event(4, 1))
        for value: UInt64 in [1, 2, 0] {
            XCTAssertThrowsError(try state.translate(event(57, value))) { error in
                XCTAssertEqual(error as? SessionOutputState.Failure,
                               .unsupportedEvent(page: 7, usage: 57, value: value))
            }
            XCTAssertEqual(state.heldUsages, [224, 4])
        }
        XCTAssertEqual(state.releaseAll().map(\.keyCode), [0, 59])
        XCTAssertTrue(state.heldUsages.isEmpty)
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

    func testStaleCrashLedgerRetainsOwnedOutputWithoutClaimingReadiness() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let report = SessionRuntimeReport(
            nonce: "owned", pid: 100, uid: 501, state: .running,
            accessibility: true, effectiveInputAccess: true, tapActive: true,
            tcpPort: 37001, inputCount: 1, outputCount: 1,
            timestamp: now.addingTimeInterval(-60), heldOutputUsages: [4, 224]
        )
        XCTAssertFalse(report.isCurrent(nonce: "owned", pid: 100, uid: 501, now: now))
        XCTAssertTrue(report.belongsTo(nonce: "owned", pid: 100, uid: 501))
        XCTAssertFalse(report.belongsTo(nonce: "foreign", pid: 100, uid: 501))
        XCTAssertFalse(report.belongsTo(nonce: "owned", pid: 101, uid: 501))
        XCTAssertFalse(report.belongsTo(nonce: "owned", pid: 100, uid: 0))
        var outputs = SessionOutputState()
        for usage in report.heldOutputUsages {
            _ = try outputs.translate(event(usage, 1))
        }
        let releases = outputs.releaseAll()
        XCTAssertEqual(releases.map(\.keyCode), [0, 59])
        XCTAssertTrue(releases.allSatisfy { !$0.isDown })
        XCTAssertTrue(outputs.heldUsages.isEmpty)
    }
}
