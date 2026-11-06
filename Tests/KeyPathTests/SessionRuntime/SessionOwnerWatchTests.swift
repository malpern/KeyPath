import Foundation
@testable import KeyPathAppKit
import XCTest

final class SessionOwnerWatchTests: XCTestCase {
    func testVerdictRetiresWhenOwnerIsGone() {
        XCTAssertEqual(SessionOwnerWatch.verdict(ownerPID: 30378, ownerAlive: false, elapsed: 0, deadline: nil), .ownerExited)
        XCTAssertNil(SessionOwnerWatch.verdict(ownerPID: 30378, ownerAlive: true, elapsed: 3600, deadline: nil))
    }

    func testOwnerExitWinsOverDeadline() {
        XCTAssertEqual(SessionOwnerWatch.verdict(ownerPID: 7, ownerAlive: false, elapsed: 20, deadline: 15), .ownerExited)
    }

    func testDeadlineBoundsAProbeWhoseOwnerIsAlive() {
        XCTAssertNil(SessionOwnerWatch.verdict(ownerPID: 7, ownerAlive: true, elapsed: 14.9, deadline: 15))
        XCTAssertEqual(SessionOwnerWatch.verdict(ownerPID: 7, ownerAlive: true, elapsed: 15, deadline: 15), .deadlineExceeded)
    }

    /// A missing --session-owner is not a dead owner; only the deadline applies.
    func testMissingOwnerIsNotTreatedAsExited() {
        XCTAssertNil(SessionOwnerWatch.verdict(ownerPID: 0, ownerAlive: false, elapsed: 1, deadline: nil))
        XCTAssertEqual(SessionOwnerWatch.verdict(ownerPID: 0, ownerAlive: false, elapsed: 16, deadline: 15), .deadlineExceeded)
    }

    func testWatchFiresOnceWhenOwnerDiesWithoutTheMainThread() {
        let alive = Locked(true)
        let fired = expectation(description: "Owner exit observed")
        let calls = Locked(0)
        let watch = SessionOwnerWatch(ownerPID: 30378, deadline: nil, interval: 0.01,
                                      isAlive: { _ in alive.value })
        { verdict in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(verdict, .ownerExited)
            calls.update { $0 += 1 }
            fired.fulfill()
        }
        alive.update { $0 = false }
        wait(for: [fired], timeout: 2)
        // A cancelled timer never delivers a second verdict.
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(calls.value, 1)
        withExtendedLifetime(watch) {}
    }

    func testReplacedHandlerReceivesTheVerdict() {
        let alive = Locked(true)
        let fired = expectation(description: "Replacement handler called")
        let watch = SessionOwnerWatch(ownerPID: 30378, deadline: nil, interval: 0.01,
                                      isAlive: { _ in alive.value }) { _ in XCTFail("Startup handler must be replaced") }
        watch.setHandler { _ in fired.fulfill() }
        alive.update { $0 = false }
        wait(for: [fired], timeout: 2)
    }

    func testWatchEndsAProbeAtItsDeadline() {
        let now = Locked(100.0)
        let fired = expectation(description: "Deadline observed")
        let watch = SessionOwnerWatch(ownerPID: 30378, deadline: 15, interval: 0.01,
                                      isAlive: { _ in true }, uptime: { now.value })
        { verdict in
            XCTAssertEqual(verdict, .deadlineExceeded)
            fired.fulfill()
        }
        now.update { $0 = 115 }
        wait(for: [fired], timeout: 2)
        withExtendedLifetime(watch) {}
    }
}

final class SessionShutdownFallbackTests: XCTestCase {
    func testOrderlyShutdownCancelsTheHardExit() {
        let fallback = SessionShutdownFallback()
        let fired = expectation(description: "Hard exit must not run")
        fired.isInverted = true
        XCTAssertTrue(fallback.arm(after: 0.05) { fired.fulfill() })
        fallback.shutdownBegins()
        wait(for: [fired], timeout: 0.3)
    }

    /// An owner exit during a shutdown already under way arms nothing.
    func testNothingIsArmedOnceShutdownBegan() {
        let fallback = SessionShutdownFallback()
        fallback.shutdownBegins()
        XCTAssertFalse(fallback.arm(after: 0) { XCTFail("Must not run") })
    }

    func testArmedFallbackRunsWhenNoShutdownStarts() {
        let fallback = SessionShutdownFallback()
        let fired = expectation(description: "Hard exit runs")
        XCTAssertTrue(fallback.arm(after: 0.01) { fired.fulfill() })
        // A second owner verdict does not arm a second exit.
        XCTAssertTrue(fallback.arm(after: 0.01) { XCTFail("Armed twice") })
        wait(for: [fired], timeout: 2)
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.lock(); defer { lock.unlock() }; return stored
    }

    func update(_ body: (inout Value) -> Void) {
        lock.lock(); body(&stored); lock.unlock()
    }
}
