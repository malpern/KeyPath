import HIDCaptureCore
import XCTest

final class CaptureBrandMotionTests: XCTestCase {
    private let start: UInt64 = 1_000_000_000

    func testCompletionAndMotionStayBounded() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "brand", expected: "abcd", timeoutMs: 2000,
            settleMs: 100, focused: true, nowNs: start
        ))
        session.record(
            phase: .down, keyCode: 0, characters: "a", modifiers: 0,
            isRepeat: false, nowNs: start + 10
        )
        let snapshot = session.snapshot(nowNs: start + 20)
        let motion = CaptureBrandMotion.resolve(
            snapshot: snapshot, nowNs: start + 20, reduceMotion: false
        )

        XCTAssertEqual(motion.completion, 0.25, accuracy: 0.001)
        XCTAssertTrue((0 ... 1).contains(motion.breath))
        XCTAssertTrue((0 ... 1).contains(motion.eventPulse))
        XCTAssertTrue((0 ... 1).contains(motion.glintPosition))
    }

    func testEventPulseDecaysWithoutInventingProgress() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "pulse", expected: "ab", timeoutMs: 2000,
            settleMs: 100, focused: true, nowNs: start
        ))
        session.record(
            phase: .down, keyCode: 0, characters: "a", modifiers: 0,
            isRepeat: false, nowNs: start + 10
        )
        let snapshot = session.snapshot(nowNs: start + 20)
        let immediate = CaptureBrandMotion.resolve(
            snapshot: snapshot, nowNs: start + 10, reduceMotion: false
        )
        let settled = CaptureBrandMotion.resolve(
            snapshot: snapshot, nowNs: start + 500_000_000, reduceMotion: false
        )

        XCTAssertEqual(immediate.eventPulse, 1, accuracy: 0.001)
        XCTAssertEqual(settled.eventPulse, 0, accuracy: 0.001)
        XCTAssertEqual(settled.completion, 0.5, accuracy: 0.001)
    }

    func testReduceMotionProducesStableEvidenceDrivenState() {
        let session = CaptureSession()
        XCTAssertTrue(session.arm(
            runID: "reduced", expected: "ab", timeoutMs: 2000,
            settleMs: 100, focused: true, nowNs: start
        ))
        let snapshot = session.snapshot(nowNs: start)
        let first = CaptureBrandMotion.resolve(
            snapshot: snapshot, nowNs: start, reduceMotion: true
        )
        let later = CaptureBrandMotion.resolve(
            snapshot: snapshot, nowNs: start + 9_000_000_000, reduceMotion: true
        )

        XCTAssertEqual(first, later)
        XCTAssertEqual(first.eventPulse, 0)
    }
}
