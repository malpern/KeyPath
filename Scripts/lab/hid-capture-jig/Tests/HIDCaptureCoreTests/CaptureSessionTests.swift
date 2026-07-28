import HIDCaptureCore
import XCTest

final class CaptureSessionTests: XCTestCase {
    private let start: UInt64 = 1_000_000_000

    func testExactSequencePassesOnlyAfterReleaseAndSettle() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "exact", expected: "qw", timeoutMs: 2_000,
            settleMs: 100, focused: true, nowNs: start
        ))
        session.record(phase: .down, keyCode: 12, characters: "q", modifiers: 0, isRepeat: false, nowNs: start + 10)
        session.record(phase: .up, keyCode: 12, characters: "", modifiers: 0, isRepeat: false, nowNs: start + 20)
        session.record(phase: .down, keyCode: 13, characters: "w", modifiers: 0, isRepeat: false, nowNs: start + 30)
        session.record(phase: .up, keyCode: 13, characters: "", modifiers: 0, isRepeat: false, nowNs: start + 40)

        XCTAssertEqual(session.snapshot(nowNs: start + 50).state, .capturing)
        let result = session.snapshot(nowNs: start + 100_000_041)
        XCTAssertEqual(result.state, .passed)
        XCTAssertEqual(result.received, "qw")
        XCTAssertTrue(result.allKeysReleased)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testDuplicateAndRepeatFailWithExactEvidence() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "repeat", expected: "aa", timeoutMs: 2_000,
            settleMs: 100, focused: true, nowNs: start
        ))
        session.record(phase: .down, keyCode: 0, characters: "a", modifiers: 0, isRepeat: false, nowNs: start + 10)
        session.record(phase: .down, keyCode: 0, characters: "a", modifiers: 0, isRepeat: true, nowNs: start + 20)
        let result = session.snapshot(nowNs: start + 30)
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.repeatEvents, 1)
        XCTAssertEqual(result.duplicateDownEvents, 1)
        XCTAssertEqual(result.pressedKeyCodes, [0])
    }

    func testWrongOrderFailsAtFirstMismatchedCharacter() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "order", expected: "abc", timeoutMs: 2_000,
            settleMs: 100, focused: true, nowNs: start
        ))
        session.record(phase: .down, keyCode: 0, characters: "a", modifiers: 0, isRepeat: false, nowNs: start + 10)
        session.record(phase: .up, keyCode: 0, characters: "", modifiers: 0, isRepeat: false, nowNs: start + 20)
        session.record(phase: .down, keyCode: 2, characters: "c", modifiers: 0, isRepeat: false, nowNs: start + 30)
        let result = session.snapshot(nowNs: start + 40)
        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(result.issues.contains { $0.contains("character 1") })
    }

    func testTimeoutReportsMissingAndStuckKeys() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "timeout", expected: "ab", timeoutMs: 250,
            settleMs: 50, focused: true, nowNs: start
        ))
        session.record(phase: .down, keyCode: 0, characters: "a", modifiers: 0, isRepeat: false, nowNs: start + 10)
        let result = session.snapshot(nowNs: start + 250_000_001)
        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(result.issues.contains { $0.contains("missing 1") })
        XCTAssertTrue(result.issues.contains { $0.contains("unreleased key") })
    }

    func testLateInputCannotTurnTimedOutFailureIntoPass() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "late", expected: "a", timeoutMs: 250,
            settleMs: 50, focused: true, nowNs: start
        ))
        XCTAssertEqual(session.snapshot(nowNs: start + 250_000_001).state, .failed)
        session.record(phase: .down, keyCode: 0, characters: "a", modifiers: 0, isRepeat: false, nowNs: start + 300_000_000)
        session.record(phase: .up, keyCode: 0, characters: "", modifiers: 0, isRepeat: false, nowNs: start + 300_000_010)
        let result = session.snapshot(nowNs: start + 400_000_000)
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.received, "a")
    }

    func testFocusLossFailsClosed() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "focus", expected: "a", timeoutMs: 2_000,
            settleMs: 100, focused: true, nowNs: start
        ))
        session.record(phase: .down, keyCode: 0, characters: "a", modifiers: 0, isRepeat: false, nowNs: start + 5)
        session.noteFocus(false, nowNs: start + 10)
        let result = session.snapshot(nowNs: start + 20)
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(result.issues, ["capture focus was lost"])
    }

    func testArmedSessionCanRecoverFocusBeforeFirstInput() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "focus-recovery", expected: "a", timeoutMs: 2_000,
            settleMs: 100, focused: true, nowNs: start
        ))
        session.noteFocus(false, nowNs: start + 10)
        XCTAssertEqual(session.snapshot(nowNs: start + 20).state, .armed)
        session.noteFocus(true, nowNs: start + 30)
        session.record(phase: .down, keyCode: 0, characters: "a", modifiers: 0, isRepeat: false, nowNs: start + 40)
        session.record(phase: .up, keyCode: 0, characters: "", modifiers: 0, isRepeat: false, nowNs: start + 50)
        XCTAssertEqual(session.snapshot(nowNs: start + 100_000_051).state, .passed)
    }

    func testArmRejectsMissingFocusAndUnsafeBounds() {
        let session = CaptureSession()
        XCTAssertFalse(session.arm(
            runID: "not-focused", expected: "a", timeoutMs: 2_000,
            settleMs: 100, focused: false, nowNs: start
        ))
        XCTAssertEqual(session.snapshot(nowNs: start).state, .failed)
        XCTAssertFalse(session.arm(
            runID: "empty", expected: "", timeoutMs: 2_000,
            settleMs: 100, focused: true, nowNs: start
        ))
    }

    func testPassWaitsForModifierRelease() {
        let session = CaptureSession()
        let shift: UInt = 1 << 17
        XCTAssertTrue(session.arm(
            runID: "modifier-release", expected: "A", timeoutMs: 2_000,
            settleMs: 100, focused: true, nowNs: start
        ))
        session.record(phase: .flagsChanged, keyCode: 56, characters: "", modifiers: shift,
                       isRepeat: false, nowNs: start + 10)
        session.record(phase: .down, keyCode: 0, characters: "A", modifiers: shift,
                       isRepeat: false, nowNs: start + 20)
        session.record(phase: .up, keyCode: 0, characters: "", modifiers: shift,
                       isRepeat: false, nowNs: start + 30)

        var result = session.snapshot(nowNs: start + 200_000_000)
        XCTAssertEqual(result.state, .capturing)
        XCTAssertEqual(result.activeModifiers, shift)
        XCTAssertFalse(result.allKeysReleased)

        session.record(phase: .flagsChanged, keyCode: 56, characters: "", modifiers: 0,
                       isRepeat: false, nowNs: start + 200_000_010)
        result = session.snapshot(nowNs: start + 300_000_011)
        XCTAssertEqual(result.state, .passed)
        XCTAssertEqual(result.activeModifiers, 0)
        XCTAssertTrue(result.allKeysReleased)
    }
}
