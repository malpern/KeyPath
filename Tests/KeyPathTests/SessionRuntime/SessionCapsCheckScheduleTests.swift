import Foundation
import IOKit
@testable import KeyPathAppKit
import XCTest

final class SessionCapsCheckScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private let usb = SessionCapsArrivedService(registryEntryID: 42, locationID: 0x0110_0000)

    private func row(_ id: UInt64, location: UInt32?) -> SessionCapsHIDUtilTransport.ServiceRow {
        .init(registryEntryID: id, vendorID: 0x1234, productID: 1, locationID: location, serialNumber: nil,
              primaryUsagePage: 1, primaryUsage: 6)
    }

    func testWithoutArrivalsTheBackstopRunsTwoSecondsAfterTheLastCheckStarted() {
        let schedule = SessionCapsCheckSchedule()
        // A slow check (0.6 s) does not stretch the backstop: it is measured between starts.
        let lastEnd = start.addingTimeInterval(0.6)

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(1.9), lastStart: start, lastEnd: lastEnd))
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(2), lastStart: start, lastEnd: lastEnd))
    }

    func testAnArrivalMakesTheNextCheckDueAtOnce() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start.addingTimeInterval(0.01), keyboards: [usb])

        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.01), lastStart: start, lastEnd: start))
    }

    func testAnUnrecognisedOrVirtualArrivalEarnsOneCheckButNoFastWindow() {
        for keyboards in [[], [SessionCapsArrivedService(registryEntryID: 7, locationID: 0)]] {
            var schedule = SessionCapsCheckSchedule()
            schedule.keyboardArrived(at: start, keyboards: keyboards)
            XCTAssertTrue(schedule.isDue(now: start, lastStart: start, lastEnd: start))
            XCTAssertTrue(schedule.checkStarted().isEmpty)

            XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(0.5), lastStart: start,
                                          lastEnd: start.addingTimeInterval(0.1)))
        }
    }

    func testAKeyboardHidutilHasNotListedYetKeepsChecksFast() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start, keyboards: [usb])
        XCTAssertEqual(schedule.checkStarted(), [usb])
        // The first listing does not include the new service yet.
        let firstEnd = start.addingTimeInterval(0.1)
        schedule.checkFinished(at: firstEnd, resolved: [], waiting: 0)
        XCTAssertFalse(schedule.isDue(now: firstEnd.addingTimeInterval(0.2), lastStart: start, lastEnd: firstEnd))
        XCTAssertTrue(schedule.isDue(now: firstEnd.addingTimeInterval(0.25), lastStart: start, lastEnd: firstEnd))

        // The next listing includes it and the keyboard is mapped: back to the backstop.
        let second = firstEnd.addingTimeInterval(0.25)
        XCTAssertEqual(schedule.checkStarted(), [usb])
        schedule.checkFinished(at: second.addingTimeInterval(0.1), resolved: [usb], waiting: 0)
        XCTAssertFalse(schedule.isDue(now: second.addingTimeInterval(1), lastStart: second,
                                      lastEnd: second.addingTimeInterval(0.1)))
        XCTAssertNil(schedule.arrivedAt)
    }

    func testAWakeThatReRegistersListedKeyboardsCostsOneCheck() {
        var schedule = SessionCapsCheckSchedule()
        let builtIn = SessionCapsArrivedService(registryEntryID: 9, locationID: 0x0200_0000)
        schedule.keyboardArrived(at: start, keyboards: [builtIn, usb])
        let arrived = schedule.checkStarted()
        let resolved = SessionCapsCheckSchedule.resolved(
            arrived, listed: [row(9, location: 0x0200_0000), row(42, location: 0x0110_0000)], exists: { _ in true }
        )
        schedule.checkFinished(at: start.addingTimeInterval(0.3), resolved: resolved, waiting: 0)

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(1), lastStart: start,
                                      lastEnd: start.addingTimeInterval(0.3)))
    }

    func testFastChecksAreSpacedFromTheLastCheckFinishing() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start, keyboards: [usb])
        _ = schedule.checkStarted()
        let lastEnd = start.addingTimeInterval(0.4)
        schedule.checkFinished(at: lastEnd, resolved: [], waiting: 0)

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(0.6), lastStart: start, lastEnd: lastEnd))
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.65), lastStart: start, lastEnd: lastEnd))
    }

    func testAWaitingKeyboardKeepsChecksFastUntilTheWaitLimit() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start, keyboards: [usb])
        _ = schedule.checkStarted()
        // Keys held at plug-in: listed, but not admitted yet.
        let late = start.addingTimeInterval(10)
        schedule.checkFinished(at: late, resolved: [usb], waiting: 1)
        XCTAssertTrue(schedule.isDue(now: late.addingTimeInterval(0.25), lastStart: late, lastEnd: late))

        let expired = start.addingTimeInterval(SessionCapsCheckSchedule.waitLimit)
        schedule.checkFinished(at: expired, resolved: [], waiting: 1)
        XCTAssertFalse(schedule.isDue(now: expired.addingTimeInterval(0.5), lastStart: expired, lastEnd: expired))
    }

    func testAStaleArrivalDoesNotShortenANewOnesWindow() {
        var schedule = SessionCapsCheckSchedule()
        // No check succeeded after this arrival (hidutil unavailable).
        schedule.keyboardArrived(at: start, keyboards: [SessionCapsArrivedService(registryEntryID: 5, locationID: 1)])
        let later = start.addingTimeInterval(120)
        schedule.keyboardArrived(at: later, keyboards: [usb])

        XCTAssertEqual(schedule.arrivedAt, later)
        XCTAssertEqual(schedule.unlisted, [usb])
    }

    func testAnArrivalDuringACheckIsNotLostWhenThatCheckStarted() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(at: start, keyboards: [usb])
        _ = schedule.checkStarted()
        // A second keyboard arrives while the first check is still in flight.
        let second = SessionCapsArrivedService(registryEntryID: 43, locationID: 0x0120_0000)
        schedule.keyboardArrived(at: start.addingTimeInterval(0.05), keyboards: [second])
        schedule.checkFinished(at: start.addingTimeInterval(0.1), resolved: [usb], waiting: 0)

        XCTAssertTrue(schedule.arrivalPending)
        XCTAssertEqual(schedule.unlisted, [second])
    }

    func testAnArrivedServiceIsResolvedByItsIDItsLocationOrItsDeparture() {
        let secondInterface = SessionCapsArrivedService(registryEntryID: 50, locationID: 0x0300_0000)
        let unplugged = SessionCapsArrivedService(registryEntryID: 60, locationID: 0x0400_0000)
        let lagging = SessionCapsArrivedService(registryEntryID: 70, locationID: 0x0500_0000)
        let unreadable = SessionCapsArrivedService(registryEntryID: 80, locationID: nil)

        let resolved = SessionCapsCheckSchedule.resolved(
            [usb, secondInterface, unplugged, lagging, unreadable],
            // The shared NKRO interface is not listed itself, but its board's primary one is.
            listed: [row(42, location: 0x0110_0000), row(49, location: 0x0300_0000), row(1, location: nil)],
            exists: { $0 != 60 && $0 != 80 ? true : ($0 == 60 ? false : nil) }
        )
        XCTAssertEqual(resolved, [usb, secondInterface, unplugged])
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
        var arrivals: [[UInt64]] = []
        let monitor = SessionCapsKeyboardArrivalMonitor(emitsKeyboardUsages: { answers[$0] ?? false }) {
            arrivals.append($0.map(\.registryEntryID))
        }
        func service(_ id: UInt64) -> SessionCapsArrivedService {
            .init(registryEntryID: id, locationID: 1)
        }

        monitor.reportArrivals([service(2)])
        XCTAssertEqual(arrivals, [], "a readable non-keyboard service (a mouse) is not an arrival")
        monitor.reportArrivals([service(1)])
        XCTAssertEqual(arrivals, [[1]])
        monitor.reportArrivals([service(3)])
        XCTAssertEqual(arrivals.last, [], "an unreadable capability still schedules a check, with nothing to look for")
        monitor.reportArrivals([service(0)])
        XCTAssertEqual(arrivals.last, [], "an unreadable registry ID still schedules a check")
        monitor.reportArrivals([service(2), service(1), service(3)])
        XCTAssertEqual(arrivals.last, [1], "one notification batch is one arrival; only keyboards are looked for")
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
        // hidutil's own listing decides whether a keyboard is attached, so a
        // predicate that stops recognising keyboards fails instead of skipping.
        let attached = (try? SessionCapsHIDUtilTransport.keyboards().keyboards.count) ?? 0
        try XCTSkipIf(attached == 0, "no keyboard attached to this machine (a headless runner)")
        XCTAssertGreaterThan(keyboards, 0, "hidutil lists \(attached) keyboard(s), but none reads as one")
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
