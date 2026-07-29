import HIDCaptureCore
import XCTest

final class KeycapBurstModelTests: XCTestCase {
    func testOnlyKeyDownEventsBecomeKeycaps() {
        let events = [
            event(1, .down, "q", at: 100),
            event(2, .up, at: 110),
            event(3, .flagsChanged, at: 120),
        ]

        let output = KeycapBurstModel.resolve(
            events: events, pressedKeyCodes: [12], nowNs: 130, reduceMotion: false
        )

        XCTAssertEqual(output.items.map(\.label), ["Q"])
        XCTAssertEqual(output.totalPresses, 1)
    }

    func testDenseBurstIsCappedAndRaisesIntensity() {
        let events = (1 ... 30).map { index in
            event(index, .down, "x", at: 1_000_000_000 + UInt64(index) * 4_000_000)
        }

        let output = KeycapBurstModel.resolve(
            events: events,
            pressedKeyCodes: [],
            nowNs: 2_050_000_000,
            reduceMotion: false,
            limit: 10
        )

        XCTAssertEqual(output.items.count, 10)
        XCTAssertEqual(output.items.map(\.sequence), Array(21 ... 30))
        XCTAssertGreaterThanOrEqual(output.intensity, 0.85)
        XCTAssertEqual(output.presentedPresses, 30)
        XCTAssertTrue(output.isAnimating)
    }

    func testFasterThanDisplayInputIsPresentedInOrderAtReadableCadence() {
        let events = (1 ... 5).map { index in
            event(index, .down, String(index), at: 1_000_000_000 + UInt64(index))
        }

        let early = KeycapBurstModel.resolve(
            events: events,
            pressedKeyCodes: [],
            nowNs: 1_050_000_000,
            reduceMotion: false
        )
        let later = KeycapBurstModel.resolve(
            events: events,
            pressedKeyCodes: [],
            nowNs: 1_160_000_000,
            reduceMotion: false
        )

        XCTAssertEqual(early.presentedPresses, 2)
        XCTAssertEqual(early.items.map(\.label), ["1", "2"])
        XCTAssertEqual(later.presentedPresses, 5)
        XCTAssertEqual(later.items.map(\.label), ["1", "2", "3", "4", "5"])
    }

    func testPressCompressesImmediatelyThenReleases() {
        let input = [event(1, .down, "a", at: 1_000_000_000)]
        let initial = KeycapBurstModel.resolve(
            events: input, pressedKeyCodes: [12], nowNs: 1_000_000_000, reduceMotion: false
        )
        let released = KeycapBurstModel.resolve(
            events: input, pressedKeyCodes: [], nowNs: 1_180_000_000, reduceMotion: false
        )

        XCTAssertEqual(initial.items[0].pressDepth, 1, accuracy: 0.001)
        XCTAssertTrue(initial.items[0].isPressed)
        XCTAssertEqual(released.items[0].pressDepth, 0, accuracy: 0.001)
        XCTAssertFalse(released.items[0].isPressed)
    }

    func testOldKeycapsAgeOut() {
        let output = KeycapBurstModel.resolve(
            events: [event(1, .down, "a", at: 1_000_000_000)],
            pressedKeyCodes: [],
            nowNs: 1_900_000_001,
            reduceMotion: false
        )

        XCTAssertTrue(output.items.isEmpty)
    }

    func testReducedMotionKeepsStackPositionStableWhileItIsVisible() {
        let input = [event(1, .down, "a", at: 1_000_000_000)]
        let early = KeycapBurstModel.resolve(
            events: input, pressedKeyCodes: [12], nowNs: 1_020_000_000, reduceMotion: true
        )
        let later = KeycapBurstModel.resolve(
            events: input, pressedKeyCodes: [], nowNs: 1_400_000_000, reduceMotion: true
        )

        XCTAssertEqual(early.items[0].xOffset, later.items[0].xOffset)
        XCTAssertEqual(early.items[0].yOffset, later.items[0].yOffset)
        XCTAssertEqual(early.items[0].scale, later.items[0].scale)
        XCTAssertEqual(early.items[0].pressDepth, 0)
    }

    func testSpecialKeyLabelsAreReadable() {
        XCTAssertEqual(KeycapBurstModel.label(for: event(1, .down, " ", at: 0)), "SPACE")
        XCTAssertEqual(KeycapBurstModel.label(for: event(1, .down, "\r", at: 0)), "RETURN")
        XCTAssertEqual(KeycapBurstModel.label(for: event(1, .down, "\u{7f}", at: 0)), "DELETE")
        XCTAssertEqual(KeycapBurstModel.label(for: event(1, .down, "", at: 0, keyCode: 53)), "ESC")
    }

    private func event(
        _ sequence: Int,
        _ phase: CapturedEventPhase,
        _ characters: String = "",
        at timestampNs: UInt64,
        keyCode: UInt16 = 12
    ) -> CapturedKeyEvent {
        CapturedKeyEvent(
            sequence: sequence,
            phase: phase,
            keyCode: keyCode,
            characters: characters,
            modifiers: 0,
            isRepeat: false,
            timestampNs: timestampNs
        )
    }
}
