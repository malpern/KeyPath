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
        schedule.keyboardArrived(keyboards: [usb])

        // The previous check finished a second ago, well past the pause.
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.01), lastStart: start.addingTimeInterval(-1.5),
                                     lastEnd: start.addingTimeInterval(-1)))
    }

    func testAnUnrecognisedOrVirtualArrivalEarnsOneCheckButNoFastChecks() {
        for keyboards in [[], [SessionCapsArrivedService(registryEntryID: 7, locationID: 0)]] {
            var schedule = SessionCapsCheckSchedule()
            schedule.keyboardArrived(keyboards: keyboards)
            XCTAssertTrue(schedule.isDue(now: start, lastStart: .distantPast, lastEnd: .distantPast))
            XCTAssertTrue(schedule.checkStarted(at: start, lastStart: .distantPast).isEmpty)

            XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(0.5), lastStart: start,
                                          lastEnd: start.addingTimeInterval(0.1)))
        }
    }

    func testAKeyboardHidutilHasNotListedYetGetsFastChecks() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(keyboards: [usb])
        XCTAssertEqual(schedule.checkStarted(at: start, lastStart: .distantPast), [usb])
        // The first listing does not include the new service yet.
        let firstEnd = start.addingTimeInterval(0.1)
        schedule.checkFinished(resolved: [])
        XCTAssertFalse(schedule.isDue(now: firstEnd.addingTimeInterval(0.2), lastStart: start, lastEnd: firstEnd))
        XCTAssertTrue(schedule.isDue(now: firstEnd.addingTimeInterval(0.25), lastStart: start, lastEnd: firstEnd))

        // The next listing includes it: back to the backstop.
        let second = firstEnd.addingTimeInterval(0.25)
        XCTAssertEqual(schedule.checkStarted(at: start, lastStart: .distantPast), [usb])
        schedule.checkFinished(resolved: [usb])
        XCTAssertFalse(schedule.isDue(now: second.addingTimeInterval(1), lastStart: second,
                                      lastEnd: second.addingTimeInterval(0.1)))
    }

    func testFastChecksAreCappedByCountForAServiceHidutilNeverLists() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(keyboards: [usb])
        var now = start
        var checks = 0
        while schedule.isDue(now: now, lastStart: now, lastEnd: now.addingTimeInterval(-1)), checks < 100 {
            _ = schedule.checkStarted(at: start, lastStart: .distantPast)
            schedule.checkFinished(resolved: [])
            checks += 1
            now = now.addingTimeInterval(0.3)
        }
        XCTAssertEqual(checks, SessionCapsCheckSchedule.fastChecks)
        XCTAssertTrue(schedule.unlisted.isEmpty)
    }

    func testAWakeThatReRegistersListedKeyboardsCostsOneCheck() {
        var schedule = SessionCapsCheckSchedule()
        let builtIn = SessionCapsArrivedService(registryEntryID: 9, locationID: 0x0200_0000)
        schedule.keyboardArrived(keyboards: [builtIn, usb])
        let arrived = schedule.checkStarted(at: start, lastStart: .distantPast)
        let resolved = SessionCapsCheckSchedule.resolved(
            arrived, listed: [row(9, location: 0x0200_0000), row(42, location: 0x0110_0000)], exists: { _ in true }
        )
        schedule.checkFinished(resolved: resolved)

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(1), lastStart: start,
                                      lastEnd: start.addingTimeInterval(0.3)))
    }

    func testFastChecksAreSpacedFromTheLastCheckFinishing() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(keyboards: [usb])
        _ = schedule.checkStarted(at: start, lastStart: .distantPast)
        let lastEnd = start.addingTimeInterval(0.4)
        schedule.checkFinished(resolved: [])

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(0.6), lastStart: start, lastEnd: lastEnd))
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.65), lastStart: start, lastEnd: lastEnd))
    }

    func testAFailedCheckHandsOverToTheBackstop() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(keyboards: [usb])
        _ = schedule.checkStarted(at: start, lastStart: .distantPast)
        schedule.checkFailed()

        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(1), lastStart: start,
                                      lastEnd: start.addingTimeInterval(0.1)))
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(2), lastStart: start,
                                     lastEnd: start.addingTimeInterval(0.1)))
    }

    @MainActor
    func testABackoffIsDroppedOnlyOnceItsKeyboardIsGone() {
        // 1 is listed, 2 is missing from this listing but still registered, 3 is gone,
        // 4's existence can't be read.
        let departed = SessionRuntimeWorker.departedBackoffs(
            [1, 2, 3, 4], listed: [1], exists: { id in id == 3 ? false : (id == 4 ? nil : true) }
        )
        XCTAssertEqual(departed, [3])
    }

    func testOnlyNonVirtualKeyboardsAreTracked() {
        var schedule = SessionCapsCheckSchedule()
        let virtual = SessionCapsArrivedService(registryEntryID: 7, locationID: 0)
        // A virtual keyboard (Karabiner, a VM's platform keyboard) is not timed.
        XCTAssertEqual(schedule.keyboardArrived(keyboards: [virtual, usb]), [usb])
        XCTAssertEqual(schedule.keyboardArrived(keyboards: [virtual]), [])
    }

    func testRepeatedArrivalsShareOneEarlyCheckBudget() {
        var schedule = SessionCapsCheckSchedule()
        var now = start
        var lastStart = Date.distantPast
        var early = 0
        // A flapping device re-registers every 0.3 s, and every listing shows it.
        for _ in 0 ..< 30 {
            schedule.keyboardArrived(keyboards: [usb])
            if schedule.isDue(now: now, lastStart: lastStart, lastEnd: now.addingTimeInterval(-0.3)),
               now.timeIntervalSince(lastStart) < SessionCapsCheckSchedule.backstop || lastStart == .distantPast
            {
                let arrived = schedule.checkStarted(at: now, lastStart: lastStart)
                schedule.checkFinished(resolved: arrived)
                if now.timeIntervalSince(lastStart) < SessionCapsCheckSchedule.backstop { early += 1 }
                lastStart = now
            }
            now = now.addingTimeInterval(0.3)
        }
        // 9 s of flapping: the first check (after idle) plus the budget's early ones,
        // then nothing early until the window slides.
        XCTAssertEqual(early, SessionCapsCheckSchedule.earlyBudget)
        XCTAssertFalse(schedule.isDue(now: now, lastStart: now.addingTimeInterval(-1), lastEnd: now.addingTimeInterval(-1)))
        XCTAssertTrue(schedule.isDue(now: now, lastStart: now.addingTimeInterval(-2), lastEnd: now.addingTimeInterval(-1)),
                      "the backstop still runs")
    }

    func testASecondKeyboardSoonAfterTheFirstStillGetsEarlyChecks() {
        var schedule = SessionCapsCheckSchedule()
        var now = start
        var lastStart = Date.distantPast
        // The first keyboard never shows up in hidutil's list and uses all its fast checks.
        schedule.keyboardArrived(keyboards: [usb])
        for _ in 0 ..< SessionCapsCheckSchedule.fastChecks {
            XCTAssertTrue(schedule.isDue(now: now, lastStart: lastStart, lastEnd: now.addingTimeInterval(-0.3)))
            _ = schedule.checkStarted(at: now, lastStart: lastStart)
            schedule.checkFinished(resolved: [])
            lastStart = now
            now = now.addingTimeInterval(0.3)
        }
        // A second keyboard is plugged in a moment later.
        schedule.keyboardArrived(keyboards: [SessionCapsArrivedService(registryEntryID: 43, locationID: 0x0120_0000)])
        XCTAssertTrue(schedule.isDue(now: now, lastStart: lastStart, lastEnd: now.addingTimeInterval(-0.3)))
    }

    func testAnEarlyCheckWaitsForThePauseAfterTheLastOneFinished() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(keyboards: [usb])
        XCTAssertFalse(schedule.isDue(now: start.addingTimeInterval(0.1), lastStart: start, lastEnd: start))
        XCTAssertTrue(schedule.isDue(now: start.addingTimeInterval(0.25), lastStart: start, lastEnd: start))
    }

    func testAnArrivalDuringACheckIsNotLostWhenThatCheckStarted() {
        var schedule = SessionCapsCheckSchedule()
        schedule.keyboardArrived(keyboards: [usb])
        _ = schedule.checkStarted(at: start, lastStart: .distantPast)
        // A second keyboard arrives while the first check is still in flight.
        let second = SessionCapsArrivedService(registryEntryID: 43, locationID: 0x0120_0000)
        schedule.keyboardArrived(keyboards: [second])
        schedule.checkFinished(resolved: [usb])

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
    func testMonitorStartsWithoutReportingKeyboardsAlreadyConnected() throws {
        var arrivals = 0
        let monitor = SessionCapsKeyboardArrivalMonitor(emitsKeyboardUsages: { _ in true }) { _ in arrivals += 1 }
        defer { monitor.stop() }

        try XCTSkipUnless(monitor.start(), "IOKit notifications unavailable on this host")
        XCTAssertFalse(monitor.start(), "a started monitor refuses a second start")
        // Every service counts as a keyboard here, so a zero is the startup drain at work.
        XCTAssertEqual(arrivals, 0, "services present at start are inventory, not arrivals")
    }

    /// The production path: classify off the main thread, deliver on the main run loop.
    @MainActor
    func testArrivalsAreClassifiedOffTheMainThreadAndDeliveredOnIt() throws {
        var delivered: [[UInt64]] = []
        let monitor = SessionCapsKeyboardArrivalMonitor(emitsKeyboardUsages: { id in
            XCTAssertFalse(Thread.isMainThread, "classification must stay off the event tap's run loop")
            return id == 1
        }) { delivered.append($0.map(\.registryEntryID)) }
        defer { monitor.stop() }
        try XCTSkipUnless(monitor.start(), "IOKit notifications unavailable on this host")

        monitor.classifyAndDeliver([.init(registryEntryID: 1, locationID: 1), .init(registryEntryID: 2, locationID: 2)])
        let deadline = Date().addingTimeInterval(5)
        while delivered.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(delivered, [[1]])
    }

    @MainActor
    func testAClassificationFinishingAfterStopIsDropped() throws {
        var delivered = 0
        let monitor = SessionCapsKeyboardArrivalMonitor(emitsKeyboardUsages: { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return true
        }) { _ in delivered += 1 }
        try XCTSkipUnless(monitor.start(), "IOKit notifications unavailable on this host")

        monitor.classifyAndDeliver([.init(registryEntryID: 1, locationID: 1)])
        monitor.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(delivered, 0)
    }

    /// The arrival side reads LocationID from IOKit, the listing side from hidutil's
    /// JSON; matching by location needs the two to agree.
    func testIOKitAndHidutilAgreeOnLocationIDs() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KEYPATH_LIVE_CAPS_FLEET"] == "1",
                          "set KEYPATH_LIVE_CAPS_FLEET=1 to check attached keyboards")
        let rows = try SessionCapsHIDUtilTransport.parseServiceRows(
            SessionCapsHIDUtilTransport.runHIDUtil(["list", "--ndjson", "--matching", "keyboard"])
        ).filter { ($0.locationID ?? 0) != 0 }
        try XCTSkipIf(rows.isEmpty, "no located keyboard attached")
        for row in rows {
            guard let matching = IORegistryEntryIDMatching(row.registryEntryID) else { continue }
            let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            guard service != 0 else { continue }
            defer { IOObjectRelease(service) }
            XCTAssertEqual(SessionCapsKeyboardArrivalMonitor.locationID(of: service), row.locationID,
                           "registry ID \(row.registryEntryID)")
        }
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
        // Reads this Mac's hardware, so it is opt-in like the fleet's live test.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KEYPATH_LIVE_CAPS_FLEET"] == "1",
                          "set KEYPATH_LIVE_CAPS_FLEET=1 to check attached keyboards")
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
    func testEachCoveredKeyboardIsTimedFromItsOwnArrival() {
        let secondary = SessionCapsArrivedService(registryEntryID: 50, locationID: 0x0300_0000)
        let timed: [SessionCapsArrivedService: Date] = [usb: start, secondary: start.addingTimeInterval(1)]
        let result = SessionRuntimeWorker.arrivalLog(
            timed, now: start.addingTimeInterval(1.4),
            // 42 by its own ID; 49 by the LocationID its NKRO interface 50 shares; 7 was
            // covered for another reason (an exclusion removed) and is not an arrival.
            covered: [(id: 42, location: 0x0110_0000), (id: 49, location: 0x0300_0000), (id: 7, location: 0x0900_0000)]
        )
        XCTAssertEqual(result.lines, [
            "[SessionCaps] Keyboard arrival mapped in 1400 ms: [42]",
            "[SessionCaps] Keyboard arrival mapped in 400 ms: [49]",
        ])
        XCTAssertTrue(result.remaining.isEmpty)
    }

    @MainActor
    func testAnArrivalThatNeverMapsIsDroppedAtTheAttributionLimit() {
        let pending = SessionRuntimeWorker.arrivalLog([usb: start], now: start.addingTimeInterval(5), covered: [])
        XCTAssertEqual(pending.remaining, [usb: start])

        let expired = SessionRuntimeWorker.arrivalLog(
            [usb: start], now: start.addingTimeInterval(SessionRuntimeWorker.arrivalAttributionLimit),
            covered: [(id: 42, location: 0x0110_0000)]
        )
        XCTAssertEqual(expired.lines, [], "an excluded or withheld arrival is not timed by a later mapping")
        XCTAssertTrue(expired.remaining.isEmpty)
    }
}
