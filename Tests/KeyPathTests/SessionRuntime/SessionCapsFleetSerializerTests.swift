import Foundation
@testable import KeyPathAppKit
import XCTest

/// The restore at exit must never run beside a keyboard check (it failed `busy`
/// and left Caps remapped after the app was killed), and no check may run after it.
final class SessionCapsFleetSerializerTests: XCTestCase {
    func testRestoreWaitsForTheCheckInFlight() {
        let serializer = SessionCapsFleetSerializer(label: "test.caps-fleet.in-flight")
        let events = Events()
        let checkStarted = expectation(description: "check started")
        let release = DispatchSemaphore(value: 0)
        serializer.check {
            checkStarted.fulfill()
            release.wait()
            events.append("check finished")
        }
        wait(for: [checkStarted], timeout: 5)

        let restoredEarly = expectation(description: "restore ran beside the check")
        restoredEarly.isInverted = true
        let restored = expectation(description: "restore ran")
        Thread.detachNewThread {
            serializer.restoreAtExit {
                events.append("restored")
                restoredEarly.fulfill()
                restored.fulfill()
            }
        }
        // While the check holds its locks, the restore must not run.
        wait(for: [restoredEarly], timeout: 0.3)
        release.signal()
        wait(for: [restored], timeout: 5)
        XCTAssertEqual(events.all, ["check finished", "restored"])
    }

    func testNoCheckRunsAfterTheRestore() {
        let serializer = SessionCapsFleetSerializer(label: "test.caps-fleet.after")
        let events = Events()
        serializer.restoreAtExit { events.append("restored") }
        serializer.check { events.append("late check") }
        // The queue is serial: this returns only after the late check was handled.
        serializer.restoreAtExit {}
        XCTAssertEqual(events.all, ["restored"], "a check after the restore could re-apply the mapping")
    }

    func testChecksRunInOrderUntilTheRestore() {
        let serializer = SessionCapsFleetSerializer(label: "test.caps-fleet.order")
        let events = Events()
        serializer.check { events.append("check 1") }
        serializer.check { events.append("check 2") }
        serializer.restoreAtExit { events.append("restored") }
        XCTAssertEqual(events.all, ["check 1", "check 2", "restored"])
    }

    func testRestoreErrorsReachTheCaller() {
        enum Failure: Error { case busy }
        let serializer = SessionCapsFleetSerializer(label: "test.caps-fleet.error")
        XCTAssertThrowsError(try serializer.restoreAtExit { throw Failure.busy }) { error in
            XCTAssertEqual(error as? Failure, .busy)
        }
    }
}

private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    var all: [String] {
        lock.withLock { items }
    }

    func append(_ item: String) {
        lock.withLock { items.append(item) }
    }
}
