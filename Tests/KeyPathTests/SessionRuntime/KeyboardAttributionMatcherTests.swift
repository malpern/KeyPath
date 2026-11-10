@testable import KeyPathAppKit
import XCTest

final class KeyboardAttributionMatcherTests: XCTestCase {
    private typealias Matcher = KeyboardAttributionMatcher

    private let laptop: UInt64 = 0x100
    private let external: UInt64 = 0x200
    private let rightArrow: UInt32 = 0x4F
    private let letterA: UInt32 = 0x04

    private func ms(_ value: Double) -> UInt64 {
        UInt64(value * 1_000_000)
    }

    private func hid(_ device: UInt64, _ usage: UInt32, down: Bool, at time: Double) -> Matcher.HIDValue {
        Matcher.HIDValue(device: device, usage: usage, isDown: down, timeNs: ms(time))
    }

    private func tap(_ usage: UInt32, down: Bool, repeat isRepeat: Bool = false, at time: Double) -> Matcher.TapEvent {
        Matcher.TapEvent(usage: usage, isDown: down, isRepeat: isRepeat, timeNs: ms(time))
    }

    // MARK: - Presses

    func testPressIsCreditedToTheOnlyKeyboardThatPressedIt() {
        var matcher = Matcher()
        matcher.record(hid(laptop, letterA, down: true, at: 100))
        XCTAssertEqual(matcher.attribute(tap(letterA, down: true, at: 101.2), nowNs: ms(101.2)), .keyboard(laptop))
        XCTAssertTrue(matcher.unconsumed.isEmpty, "the matched HID value is consumed")
    }

    func testPressTrailingHIDWithinTheLookBehindIsCredited() {
        var matcher = Matcher()
        matcher.record(hid(external, letterA, down: true, at: 100))
        // The overlap run measured a tap trailing HID by up to 27 ms.
        XCTAssertEqual(matcher.attribute(tap(letterA, down: true, at: 127), nowNs: ms(127)), .keyboard(external))
    }

    func testPressTrailingHIDBeyondTheLookBehindFallsBack() {
        var matcher = Matcher()
        matcher.record(hid(external, letterA, down: true, at: 100))
        XCTAssertEqual(matcher.attribute(tap(letterA, down: true, at: 131), nowNs: ms(136)), .fallback(.noMatch))
        XCTAssertTrue(matcher.unconsumed.isEmpty, "a HID value outside the window is pruned, not kept for later")
    }

    func testPressAheadOfHIDWaitsAndIsCreditedWhenHIDArrives() {
        var matcher = Matcher()
        let press = tap(rightArrow, down: true, at: 200)
        XCTAssertEqual(matcher.attribute(press, nowNs: ms(200)), .wait)
        // The tap ran up to 3.9 ms ahead of HID in the overlap run.
        matcher.record(hid(laptop, rightArrow, down: true, at: 203.9))
        XCTAssertEqual(matcher.attribute(press, nowNs: ms(204)), .keyboard(laptop))
    }

    func testPressWithNoHIDFallsBackOnceTheLookAheadHasPassed() {
        var matcher = Matcher()
        let press = tap(rightArrow, down: true, at: 200)
        XCTAssertEqual(matcher.attribute(press, nowNs: ms(204.9)), .wait)
        XCTAssertEqual(matcher.attribute(press, nowNs: ms(205)), .fallback(.noMatch))
    }

    func testCandidatesFromTwoKeyboardsFallBackAndLeaveTheOtherForTheNextPress() {
        var matcher = Matcher()
        matcher.record(hid(laptop, rightArrow, down: true, at: 300))
        matcher.record(hid(external, rightArrow, down: true, at: 302))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: true, at: 302.5), nowNs: ms(302.5)), .fallback(.ambiguous))
        // The closest candidate (external, 0.5 ms away) was consumed.
        XCTAssertEqual(matcher.unconsumed, [hid(laptop, rightArrow, down: true, at: 300)])
    }

    func testTwoCandidatesFromOneKeyboardAreStillCredited() {
        var matcher = Matcher()
        matcher.record(hid(laptop, letterA, down: true, at: 400))
        matcher.record(hid(laptop, letterA, down: true, at: 410))
        XCTAssertEqual(matcher.attribute(tap(letterA, down: true, at: 411), nowNs: ms(411)), .keyboard(laptop))
        XCTAssertEqual(matcher.unconsumed, [hid(laptop, letterA, down: true, at: 400)], "the closer value was consumed")
    }

    func testOnlyTheSameKeyAndDirectionAreCandidates() {
        var matcher = Matcher()
        matcher.record(hid(laptop, letterA, down: true, at: 500))
        matcher.record(hid(external, rightArrow, down: false, at: 500))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: true, at: 501), nowNs: ms(510)), .fallback(.noMatch))
        XCTAssertEqual(matcher.unconsumed.count, 2, "non-candidates are left untouched")
    }

    // MARK: - Releases follow the press

    func testReleaseFollowsThePressEvenWhenHIDPairsItWithAnotherKeyboard() {
        var matcher = Matcher()
        matcher.record(hid(laptop, rightArrow, down: true, at: 600))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: true, at: 601), nowNs: ms(601)), .keyboard(laptop))
        // macOS merged the external keyboard's press; its release ends the key.
        matcher.record(hid(external, rightArrow, down: true, at: 620))
        matcher.record(hid(external, rightArrow, down: false, at: 640))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: false, at: 641), nowNs: ms(641)), .keyboard(laptop))
    }

    func testReleaseOfAPressThatFellBackFallsBack() {
        var matcher = Matcher()
        let press = tap(letterA, down: true, at: 700)
        XCTAssertEqual(matcher.attribute(press, nowNs: ms(706)), .fallback(.noMatch))
        XCTAssertEqual(matcher.attribute(tap(letterA, down: false, at: 750), nowNs: ms(750)), .fallback(.pressNotCredited))
    }

    func testReleaseWithNoPressFallsBack() {
        var matcher = Matcher()
        XCTAssertEqual(matcher.attribute(tap(letterA, down: false, at: 800), nowNs: ms(800)), .fallback(.noMatch))
    }

    func testReleaseNeverWaits() {
        var matcher = Matcher()
        matcher.record(hid(laptop, letterA, down: true, at: 900))
        _ = matcher.attribute(tap(letterA, down: true, at: 901), nowNs: ms(901))
        // HID's release has not arrived yet; the release is decided at once.
        XCTAssertEqual(matcher.attribute(tap(letterA, down: false, at: 950), nowNs: ms(950)), .keyboard(laptop))
    }

    // MARK: - Repeats

    func testRepeatIsCreditedWhileOnlyThePressingKeyboardHoldsTheKey() {
        var matcher = Matcher()
        matcher.record(hid(laptop, rightArrow, down: true, at: 1000))
        _ = matcher.attribute(tap(rightArrow, down: true, at: 1001), nowNs: ms(1001))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: true, repeat: true, at: 1500), nowNs: ms(1500)), .keyboard(laptop))
    }

    func testRepeatWhileTheKeyIsDownOnTwoKeyboardsFallsBack() {
        var matcher = Matcher()
        matcher.record(hid(laptop, rightArrow, down: true, at: 1000))
        _ = matcher.attribute(tap(rightArrow, down: true, at: 1001), nowNs: ms(1001))
        matcher.record(hid(external, rightArrow, down: true, at: 1200))
        XCTAssertEqual(
            matcher.attribute(tap(rightArrow, down: true, repeat: true, at: 1500), nowNs: ms(1500)),
            .fallback(.heldOnSeveralKeyboards)
        )
        // Once the other keyboard lets go, repeats are credited again.
        matcher.record(hid(external, rightArrow, down: false, at: 1550))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: true, repeat: true, at: 1600), nowNs: ms(1600)), .keyboard(laptop))
    }

    func testRepeatOfAPressThatFellBackFallsBack() {
        var matcher = Matcher()
        _ = matcher.attribute(tap(letterA, down: true, at: 1000), nowNs: ms(1010))
        XCTAssertEqual(
            matcher.attribute(tap(letterA, down: true, repeat: true, at: 1500), nowNs: ms(1500)),
            .fallback(.pressNotCredited)
        )
    }

    // MARK: - Stale candidates

    func testLateHIDOfAPressThatGaveUpIsNotCreditedToTheNextPress() {
        var matcher = Matcher()
        XCTAssertEqual(matcher.attribute(tap(letterA, down: true, at: 0), nowNs: ms(5)), .fallback(.noMatch))
        matcher.record(hid(laptop, letterA, down: true, at: 6)) // arrived after its tap gave up
        XCTAssertEqual(matcher.attribute(tap(letterA, down: false, at: 10), nowNs: ms(10)), .fallback(.pressNotCredited))
        // The external keyboard's press; its HID value has not arrived yet.
        let next = tap(letterA, down: true, at: 20)
        XCTAssertEqual(matcher.attribute(next, nowNs: ms(20)), .wait)
        matcher.record(hid(external, letterA, down: true, at: 21))
        XCTAssertEqual(matcher.attribute(next, nowNs: ms(21)), .keyboard(external))
    }

    func testMergedPressDoesNotOutliveItsReleaseAndClaimTheNextPress() {
        var matcher = Matcher()
        matcher.record(hid(laptop, rightArrow, down: true, at: 600))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: true, at: 601), nowNs: ms(601)), .keyboard(laptop))
        matcher.record(hid(external, rightArrow, down: true, at: 620)) // merged by macOS: no tap press
        matcher.record(hid(external, rightArrow, down: false, at: 640))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: false, at: 641), nowNs: ms(641)), .keyboard(laptop))
        // A laptop press whose HID value is still on its way.
        let next = tap(rightArrow, down: true, at: 645)
        XCTAssertEqual(matcher.attribute(next, nowNs: ms(645)), .wait)
        matcher.record(hid(laptop, rightArrow, down: true, at: 646))
        XCTAssertEqual(matcher.attribute(next, nowNs: ms(646)), .keyboard(laptop))
    }

    func testAmbiguousLeftoverIsClearedByTheRelease() {
        var matcher = Matcher()
        matcher.record(hid(laptop, rightArrow, down: true, at: 300))
        matcher.record(hid(external, rightArrow, down: true, at: 302))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: true, at: 302.5), nowNs: ms(302.5)), .fallback(.ambiguous))
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: false, at: 310), nowNs: ms(310)), .fallback(.pressNotCredited))
        XCTAssertTrue(matcher.unconsumed.isEmpty)
    }

    // MARK: - Device removal

    func testRemovedKeyboardNoLongerBlocksRepeats() {
        var matcher = Matcher()
        matcher.record(hid(laptop, rightArrow, down: true, at: 1000))
        _ = matcher.attribute(tap(rightArrow, down: true, at: 1001), nowNs: ms(1001))
        matcher.record(hid(external, rightArrow, down: true, at: 1200)) // unplugged while held
        matcher.removeDevice(external)
        XCTAssertEqual(matcher.attribute(tap(rightArrow, down: true, repeat: true, at: 1500), nowNs: ms(1500)), .keyboard(laptop))
        XCTAssertFalse(matcher.unconsumed.contains { $0.device == external })
    }

    func testRepeatWithNoPressSeenFallsBack() {
        var matcher = Matcher()
        XCTAssertEqual(
            matcher.attribute(tap(letterA, down: true, repeat: true, at: 100), nowNs: ms(100)),
            .fallback(.noMatch)
        )
    }

    func testLookAheadSaturatesInsteadOfOverflowing() {
        var matcher = Matcher()
        let event = Matcher.TapEvent(usage: letterA, isDown: true, isRepeat: false, timeNs: UInt64.max - 1)
        XCTAssertEqual(matcher.attribute(event, nowNs: UInt64.max - 1), .wait)
    }

    // MARK: - Bounds

    func testUnconsumedValuesAreCappedOldestFirst() {
        var matcher = Matcher(configuration: .init(capacity: 3))
        for index in 0 ..< 5 {
            matcher.record(hid(laptop, letterA, down: true, at: Double(index)))
        }
        XCTAssertEqual(matcher.unconsumed.map(\.timeNs), [ms(2), ms(3), ms(4)])
    }

    func testDefaultWindowMatchesADR048() {
        let configuration = Matcher.Configuration()
        XCTAssertEqual(configuration.lookBehindNs, 30_000_000)
        XCTAssertEqual(configuration.lookAheadNs, 5_000_000)
    }
}
