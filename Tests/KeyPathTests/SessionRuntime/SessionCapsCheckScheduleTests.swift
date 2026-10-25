import Foundation
import IOKit
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
        let monitor = SessionCapsKeyboardArrivalMonitor(emitsKeyboardUsages: { _ in true }) { arrivals += 1 }
        defer { monitor.stop() }

        XCTAssertTrue(monitor.start())
        XCTAssertFalse(monitor.start(), "a started monitor refuses a second start")
        // Every service counts as a keyboard here, so a zero is the startup drain at work.
        XCTAssertEqual(arrivals, 0, "services present at start are inventory, not arrivals")
    }

    @MainActor
    func testArrivalClassificationFailsOpen() {
        let answers: [UInt64: Bool?] = [1: true, 2: false, 3: nil]
        var arrivals = 0
        let monitor = SessionCapsKeyboardArrivalMonitor(emitsKeyboardUsages: { answers[$0] ?? false }) { arrivals += 1 }

        monitor.reportArrivals([2])
        XCTAssertEqual(arrivals, 0, "a readable non-keyboard service (a mouse) is not an arrival")
        monitor.reportArrivals([1])
        XCTAssertEqual(arrivals, 1)
        monitor.reportArrivals([3])
        XCTAssertEqual(arrivals, 2, "an unreadable capability still schedules a check")
        monitor.reportArrivals([0])
        XCTAssertEqual(arrivals, 3, "an unreadable registry ID still schedules a check")
        monitor.reportArrivals([2, 1, 2])
        XCTAssertEqual(arrivals, 4, "one notification batch is one arrival")
    }

    /// The live predicate on this Mac's own event services: at least one connected
    /// keyboard must read as one, or the monitor would never report arrivals.
    func testTheLeasePredicateRecognisesAConnectedKeyboardService() throws {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDEventService"), &iterator)
            == KERN_SUCCESS else { throw XCTSkip("IOKit service listing unavailable") }
        defer { IOObjectRelease(iterator) }
        var keyboards = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS,
               SessionCapsHIDUtilTransport.serviceEmitsKeyboardUsages(id) == true
            {
                keyboards += 1
            }
        }
        try XCTSkipIf(keyboards == 0, "no keyboard attached to this machine")
        XCTAssertGreaterThan(keyboards, 0)
    }

    @MainActor
    func testArrivalIsAttributedToANewKeyboardNotARecoveringOne() {
        let arrived = start
        // An unrelated keyboard coming back from its failure backoff is not the arrival.
        let recovered = SessionRuntimeWorker.arrivalOutcome(arrivedAt: arrived, now: start.addingTimeInterval(0.4),
                                                            added: [7], recovering: [7])
        XCTAssertNil(recovered.log)
        XCTAssertTrue(recovered.keepPending)

        let mapped = SessionRuntimeWorker.arrivalOutcome(arrivedAt: arrived, now: start.addingTimeInterval(0.4),
                                                         added: [7, 8], recovering: [7])
        XCTAssertEqual(mapped.log, "[SessionCaps] Keyboard arrival mapped in 400 ms: [8]")
        XCTAssertFalse(mapped.keepPending)
    }

    @MainActor
    func testASlowArrivalIsStillMeasuredUntilTheAttributionLimit() {
        // Plugged in with keys held: mapped only after release, well past the fast window.
        let late = SessionRuntimeWorker.arrivalOutcome(arrivedAt: start, now: start.addingTimeInterval(5),
                                                       added: [], recovering: [])
        XCTAssertTrue(late.keepPending)
        let mapped = SessionRuntimeWorker.arrivalOutcome(arrivedAt: start, now: start.addingTimeInterval(6),
                                                         added: [9], recovering: [])
        XCTAssertEqual(mapped.log, "[SessionCaps] Keyboard arrival mapped in 6000 ms: [9]")

        let expired = SessionRuntimeWorker.arrivalOutcome(
            arrivedAt: start, now: start.addingTimeInterval(SessionRuntimeWorker.arrivalAttributionLimit),
            added: [], recovering: []
        )
        XCTAssertFalse(expired.keepPending, "an arrival that never maps (excluded, withheld) is dropped")
        XCTAssertNil(SessionRuntimeWorker.arrivalOutcome(arrivedAt: nil, now: start, added: [9], recovering: []).log)
    }
}
