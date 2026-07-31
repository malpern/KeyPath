import HIDCaptureCore
import XCTest

final class TypoverBearMonitorTests: XCTestCase {
    private let start: UInt64 = 1_000_000_000

    func testBeginCreatesCountdownWithoutInventingObservedKeys() {
        let session = TypoverBearMonitorSession()
        XCTAssertTrue(session.begin(
            runID: "bear-1", caseIndex: 1, caseCount: 4,
            intervalMs: 40, wordCount: 2, scheduledText: "teh teh \n",
            startDelayMs: 1500, bearFocused: true, nowNs: start
        ))

        let snapshot = session.snapshot(nowNs: start + 1_000_000_000)
        XCTAssertEqual(snapshot.phase, .countdown)
        XCTAssertTrue(snapshot.scheduledEvents.isEmpty)
        XCTAssertEqual(snapshot.totalKeyPresses, 9)
        XCTAssertEqual(snapshot.keysPerSecond, 25, accuracy: 0.001)
    }

    func testPrepareShowsBearFocusGateWithoutStartingAKeySchedule() {
        let session = TypoverBearMonitorSession()
        XCTAssertTrue(session.prepare(
            runID: "bear-matrix", caseCount: 4,
            message: "Focus the disposable Bear note", nowNs: start
        ))

        let snapshot = session.snapshot(nowNs: start + 90_000_000_000)
        XCTAssertEqual(snapshot.phase, .waitingForBear)
        XCTAssertEqual(snapshot.caseIndex, 0)
        XCTAssertEqual(snapshot.caseCount, 4)
        XCTAssertTrue(snapshot.scheduledEvents.isEmpty)
        XCTAssertNil(snapshot.scheduledStartAtNs)
    }

    func testScheduledKeycapsFollowThePhysicalCadence() {
        let session = TypoverBearMonitorSession()
        XCTAssertTrue(session.begin(
            runID: "bear-2", caseIndex: 2, caseCount: 4,
            intervalMs: 100, wordCount: 1, scheduledText: "teh \n",
            startDelayMs: 500, bearFocused: true, nowNs: start
        ))
        XCTAssertTrue(session.update(phase: .typing))

        let first = session.snapshot(nowNs: start + 500_000_000)
        let third = session.snapshot(nowNs: start + 700_000_000)
        XCTAssertEqual(first.scheduledEvents.map(\.characters), ["t"])
        XCTAssertEqual(third.scheduledEvents.map(\.characters), ["t", "e", "h"])
        XCTAssertEqual(third.scheduledEvents.map(\.timestampNs), [
            start + 500_000_000,
            start + 600_000_000,
            start + 700_000_000,
        ])
    }

    func testAnalysisCountsAreBoundedByTheCaseWordCount() {
        let session = TypoverBearMonitorSession()
        XCTAssertTrue(session.begin(
            runID: "bear-3", caseIndex: 3, caseCount: 4,
            intervalMs: 80, wordCount: 20, scheduledText: "teh ",
            startDelayMs: 500, bearFocused: true, nowNs: start
        ))

        XCTAssertTrue(session.update(
            phase: .safeMisses,
            correctedWords: 14,
            missedWords: 6,
            message: "14 applied · 6 safe misses",
            bearFocused: true
        ))
        XCTAssertFalse(session.update(
            phase: .passed,
            correctedWords: 21,
            missedWords: 0
        ))
        let snapshot = session.snapshot(nowNs: start)
        XCTAssertEqual(snapshot.correctedWords, 14)
        XCTAssertEqual(snapshot.missedWords, 6)
        XCTAssertEqual(snapshot.phase, .safeMisses)
    }

    func testInvalidOrNonASCIIPlansFailClosed() {
        let session = TypoverBearMonitorSession()
        XCTAssertFalse(session.begin(
            runID: "", caseIndex: 0, caseCount: 0,
            intervalMs: 3, wordCount: 0, scheduledText: "é",
            startDelayMs: 0, bearFocused: false, nowNs: start
        ))
        XCTAssertEqual(session.snapshot(nowNs: start).phase, .inactive)
    }
}
