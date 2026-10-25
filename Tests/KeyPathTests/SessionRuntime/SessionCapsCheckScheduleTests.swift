import Foundation
@testable import KeyPathAppKit
import XCTest

final class SessionCapsCheckScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testWithoutArrivalsTheBackstopRunsEveryTwoSeconds() {
        let schedule = SessionCapsCheckSchedule()

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(1.9), lastCheck: start))
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(2), lastCheck: start))
    }

    func testAnArrivalMakesTheNextCheckDueAtOnce() {
        var schedule = SessionCapsCheckSchedule()
        // A check ran 10 ms ago; without the arrival the next would wait ~2 s.
        let lastCheck = start
        schedule.keyboardArrived(at: start.addingTimeInterval(0.01))

        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.01), lastCheck: lastCheck))
    }

    func testChecksStayFastForTheArrivalWindowThenReturnToTheBackstop() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start)
        schedule.checkStarted()

        // hidutil may list the new service a moment later: re-read every 0.25 s.
        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(0.2), lastCheck: start))
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.25), lastCheck: start))
        let late = start.addingTimeInterval(SessionCapsCheckSchedule.arrivalWindow + 0.1)
        XCTAssertFalse(schedule.isDue(now: late, lastCheck: late.addingTimeInterval(-0.5)))
        XCTAssertTrue(schedule.isDue(now: late, lastCheck: late.addingTimeInterval(-2)))
    }

    func testAnArrivalDuringACheckIsNotLostWhenThatCheckStarted() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start)
        schedule.checkStarted()
        // A second keyboard arrives while the first check is still in flight.
        schedule.keyboardArrived(at: start.addingTimeInterval(0.05))

        XCTAssertTrue(schedule.arrivalPending)
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.06), lastCheck: start))
    }

    @MainActor
    func testMonitorStartsWithoutReportingKeyboardsAlreadyConnected() {
        var arrivals = 0
        let monitor = SessionCapsKeyboardArrivalMonitor { arrivals += 1 }
        defer { monitor.stop() }

        XCTAssertTrue(monitor.start())
        XCTAssertFalse(monitor.start(), "a started monitor refuses a second start")
        XCTAssertEqual(arrivals, 0, "services present at start are inventory, not arrivals")
    }
}
