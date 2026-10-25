import Foundation
import IOKit
@testable import KeyPathAppKit
import XCTest

final class SessionCapsCheckScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testWithoutArrivalsTheBackstopRunsTwoSecondsAfterTheLastCheckStarted() {
        let schedule = SessionCapsCheckSchedule()
        // A slow check (0.6 s) does not stretch the backstop: it is measured between starts.
        let lastEnd = start.addingTimeInterval(0.6)

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(1.9), lastStart: start, lastEnd: lastEnd))
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(2), lastStart: start, lastEnd: lastEnd))
    }

    func testAnArrivalMakesTheNextCheckDueAtOnce() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start.addingTimeInterval(0.01), recognised: true)

        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.01), lastStart: start, lastEnd: start))
    }

    func testAnUnrecognisedArrivalEarnsOneCheckButNoFastWindow() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start, recognised: false)
        XCTAssertTrue(schedule.isDue(now: start, lastStart: start, lastEnd: start))
        schedule.checkStarted()

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(0.5), lastStart: start, lastEnd: start.addingTimeInterval(0.1)))
    }

    func testFastChecksAreSpacedFromTheLastCheckFinishing() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start, recognised: true)
        schedule.checkStarted()
        let lastEnd = start.addingTimeInterval(0.4)

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(0.6), lastStart: start, lastEnd: lastEnd))
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.65), lastStart: start, lastEnd: lastEnd))
    }

    func testAWakeThatFindsEveryKeyboardCoveredCostsOneCheck() {
        var schedule = SessionCapsCheckSchedule()
        // Wake re-registers every keyboard's event service.
        schedule.keyboardArrived(at: start, recognised: true)
        schedule.checkStarted()
        schedule.checkFinished(at: start.addingTimeInterval(0.3), waiting: 0)

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(1), lastStart: start, lastEnd: start.addingTimeInterval(0.3)))
        XCTAssertNil(schedule.arrivedAt)
    }

    func testAWaitingKeyboardKeepsChecksFastUntilTheWaitLimit() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start, recognised: true)
        schedule.checkStarted()
        // Keys held at plug-in: the keyboard stays unmapped past the 3 s window.
        let late = start.addingTimeInterval(10)
        schedule.checkFinished(at: late, waiting: 1)
        XCTAssertTrue(schedule.isDue(now: late.addingTimeInterval(0.25), lastStart: late, lastEnd: late))

        let expired = start.addingTimeInterval(SessionCapsCheckSchedule.waitLimit)
        schedule.checkFinished(at: expired, waiting: 1)
        XCTAssertFalse(schedule.isDue(now: expired.addingTimeInterval(0.5), lastStart: expired, lastEnd: expired))
    }

    func testAnArrivalDuringACheckIsNotLostWhenThatCheckStarted() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start, recognised: true)
        schedule.checkStarted()
        // A second keyboard arrives while the first check is still in flight.
        schedule.keyboardArrived(at: start.addingTimeInterval(0.05), recognised: true)

        XCTAssertTrue(schedule.arrivalPending)
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.06), lastStart: start, lastEnd: start))
    }

    @MainActor
    func testMonitorStartsWithoutReportingKeyboardsAlreadyConnected() {
        var arrivals = 0
        let monitor = SessionCapsKeyboardArrivalMonitor(emitsKeyboardUsages: { _ in true }) { _ in arrivals += 1 }
        defer { monitor.stop() }

        XCTAssertTrue(monitor.start())
        XCTAssertFalse(monitor.start(), "a started monitor refuses a second start")
        // Every service counts as a keyboard here, so a zero is the startup drain at work.
        XCTAssertEqual(arrivals, 0, "services present at start are inventory, not arrivals")
    }

    @MainActor
    func testArrivalClassificationFailsOpen() {
        let answers: [UInt64: Bool?] = [1: true, 2: false, 3: nil]
        var arrivals: [Bool] = []
        let monitor = SessionCapsKeyboardArrivalMonitor(emitsKeyboardUsages: { answers[$0] ?? false }) { arrivals.append($0) }

        monitor.reportArrivals([2])
        XCTAssertEqual(arrivals, [], "a readable non-keyboard service (a mouse) is not an arrival")
        monitor.reportArrivals([1])
        XCTAssertEqual(arrivals, [true])
        monitor.reportArrivals([3])
        XCTAssertEqual(arrivals, [true, false], "an unreadable capability still schedules an unrecognised check")
        monitor.reportArrivals([0])
        XCTAssertEqual(arrivals, [true, false, false], "an unreadable registry ID still schedules a check")
        monitor.reportArrivals([2, 1, 3])
        XCTAssertEqual(arrivals.last, true, "one notification batch is one arrival, recognised if any service is")
        XCTAssertEqual(arrivals.count, 4)
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
        // Without an attached keyboard there is nothing to recognise (a headless runner).
        try XCTSkipIf(keyboards == 0, "no keyboard attached to this machine")
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
