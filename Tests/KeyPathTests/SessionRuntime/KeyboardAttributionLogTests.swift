@testable import KeyPathAppKit
import XCTest

final class KeyboardAttributionLogTests: XCTestCase {
    private typealias Matcher = KeyboardAttributionMatcher

    private let laptop: UInt64 = 0x100
    private let external: UInt64 = 0x200
    private let letterA: UInt32 = 0x04
    private let letterB: UInt32 = 0x05

    private func ms(_ value: Double) -> UInt64 {
        UInt64(value * 1_000_000)
    }

    private func hid(_ device: UInt64, _ usage: UInt32, down: Bool, at time: Double) -> Matcher.HIDValue {
        Matcher.HIDValue(device: device, usage: usage, isDown: down, timeNs: ms(time))
    }

    private func tap(_ usage: UInt32, down: Bool, at time: Double) -> Matcher.TapEvent {
        Matcher.TapEvent(usage: usage, isDown: down, isRepeat: false, timeNs: ms(time))
    }

    func testPressWithHIDValueAlreadyRecordedIsCreditedAtOnce() {
        var log = KeyboardAttributionLog()
        log.record(hid(laptop, letterA, down: true, at: 100), nowNs: ms(100))
        log.observe(tap(letterA, down: true, at: 101), nowNs: ms(101))
        XCTAssertEqual(log.counts.credited, 1)
        XCTAssertTrue(log.pending.isEmpty)
        XCTAssertEqual(log.creditedKeyboards, [laptop])
    }

    func testPressWaitsForAHIDValueThatArrivesAfterIt() {
        var log = KeyboardAttributionLog()
        log.observe(tap(letterA, down: true, at: 100), nowNs: ms(100))
        XCTAssertEqual(log.pending.count, 1, "the tap ran ahead of HID, so it waits")
        log.record(hid(external, letterA, down: true, at: 102), nowNs: ms(102))
        XCTAssertEqual(log.counts.credited, 1)
        XCTAssertTrue(log.pending.isEmpty)
    }

    func testPressWithNoHIDValueFallsBackOnceTheLookAheadHasPassed() {
        var log = KeyboardAttributionLog()
        log.observe(tap(letterA, down: true, at: 100), nowNs: ms(100))
        log.resolve(nowNs: ms(104))
        XCTAssertEqual(log.counts.noMatch, 0, "still inside the 5 ms look-ahead")
        log.resolve(nowNs: ms(106))
        XCTAssertEqual(log.counts.noMatch, 1)
        XCTAssertTrue(log.pending.isEmpty)
    }

    func testEventsAreDecidedInTapOrder() {
        var log = KeyboardAttributionLog()
        log.observe(tap(letterA, down: true, at: 100), nowNs: ms(100))
        // B's HID value is here, but A is still waiting, so B waits behind it.
        log.record(hid(laptop, letterB, down: true, at: 100.5), nowNs: ms(100.5))
        log.observe(tap(letterB, down: true, at: 101), nowNs: ms(101))
        XCTAssertEqual(log.counts.credited, 0)
        XCTAssertEqual(log.pending.count, 2)
        log.record(hid(laptop, letterA, down: true, at: 101.5), nowNs: ms(101.5))
        XCTAssertEqual(log.counts.credited, 2)
    }

    func testPressesFromTwoKeyboardsAtOnceCountAsAmbiguous() {
        var log = KeyboardAttributionLog()
        log.record(hid(laptop, letterA, down: true, at: 100), nowNs: ms(100))
        log.record(hid(external, letterA, down: true, at: 101), nowNs: ms(101))
        log.observe(tap(letterA, down: true, at: 102), nowNs: ms(102))
        XCTAssertEqual(log.counts.ambiguous, 1)
        XCTAssertEqual(log.counts.fellBack, 1)
        XCTAssertTrue(log.creditedKeyboards.isEmpty)
    }

    func testReleaseOfAnAmbiguousPressCountsAsPressNotCredited() {
        var log = KeyboardAttributionLog()
        log.record(hid(laptop, letterA, down: true, at: 100), nowNs: ms(100))
        log.record(hid(external, letterA, down: true, at: 101), nowNs: ms(101))
        log.observe(tap(letterA, down: true, at: 102), nowNs: ms(102))
        log.record(hid(laptop, letterA, down: false, at: 150), nowNs: ms(150))
        log.observe(tap(letterA, down: false, at: 151), nowNs: ms(151))
        XCTAssertEqual(log.counts.pressNotCredited, 1)
    }

    func testOutOfOrderTapTimestampsAreClampedRatherThanTrusted() {
        var log = KeyboardAttributionLog()
        log.observe(tap(letterA, down: true, at: 100), nowNs: ms(100))
        log.observe(tap(letterB, down: true, at: 99), nowNs: ms(100))
        XCTAssertEqual(log.pending.map(\.timeNs), [ms(100), ms(100)])
    }

    func testTooManyWaitingEventsDropsTheOldestAndCountsIt() {
        var log = KeyboardAttributionLog()
        for index in 0 ... KeyboardAttributionLog.pendingLimit {
            // Presses only (a release never waits), and nowNs stays at the
            // start, so nothing can be decided yet.
            log.observe(tap(index.isMultiple(of: 2) ? letterA : letterB, down: true, at: 100), nowNs: ms(100))
        }
        XCTAssertEqual(log.pending.count, KeyboardAttributionLog.pendingLimit)
        XCTAssertEqual(log.counts.dropped, 1)
    }

    func testSummaryHasTotalsOnly() {
        var log = KeyboardAttributionLog()
        log.record(hid(laptop, letterA, down: true, at: 100), nowNs: ms(100))
        log.observe(tap(letterA, down: true, at: 101), nowNs: ms(101))
        XCTAssertEqual(log.summary(), "credited 1, fell back 0 (no match 0, two keyboards 0, held on several 0, "
            + "press not credited 0), dropped 0, keyboards 1")
    }

    // MARK: - Tap clock

    /// Apple silicon's timebase: 125/3 ns per tick.
    private let appleSilicon: (UInt64) -> UInt64 = { $0 * 125 / 3 }

    func testTapClockRecognisesNanoseconds() {
        XCTAssertEqual(KeyboardAttributionTapClock.classify(eventTimestamp: 5_000_000_000,
                                                            nowNs: 5_002_000_000, ticksToNs: appleSilicon),
                       .nanoseconds)
    }

    func testTapClockRecognisesMachTicks() {
        // 120,000,000 ticks of a 24 MHz clock is 5 s.
        XCTAssertEqual(KeyboardAttributionTapClock.classify(eventTimestamp: 120_000_000,
                                                            nowNs: 5_002_000_000, ticksToNs: appleSilicon),
                       .machTicks)
    }

    func testTapClockRefusesAnUnknownUnit() {
        XCTAssertEqual(KeyboardAttributionTapClock.classify(eventTimestamp: 42,
                                                            nowNs: 5_002_000_000, ticksToNs: appleSilicon),
                       .unusable)
    }

    func testSwitchIsOffByDefault() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KeyboardAttributionLogTests"))
        defaults.removePersistentDomain(forName: "KeyboardAttributionLogTests")
        XCTAssertFalse(KeyboardAttributionMonitor.isEnabled(defaults: defaults))
        defaults.set(true, forKey: KeyboardAttributionMonitor.enabledKey)
        XCTAssertTrue(KeyboardAttributionMonitor.isEnabled(defaults: defaults))
        defaults.removePersistentDomain(forName: "KeyboardAttributionLogTests")
    }
}
