@testable import KeyPathAppKit
import XCTest

final class KeyboardStageInteractionTests: XCTestCase {
    func testKeyDownFeedbackIsImmediate() {
        var presentation = KeyboardStageInteractionPresentation()
        let pressed = KeyboardStageInteractionState(
            pressedKeyCodes: [57],
            heldKeyCodes: [],
            phase: .press,
            revision: 1
        )

        presentation.retarget(to: pressed, at: 10, reduceMotion: false)

        XCTAssertFalse(presentation.isAnimating)
        XCTAssertEqual(presentation.levels(at: 10).pressed[57], 1)
    }

    func testKeyReleaseUsesABoundedCriticallyDampedReturn() {
        let pressed = KeyboardStageInteractionState(
            pressedKeyCodes: [57],
            heldKeyCodes: [],
            phase: .press,
            revision: 1
        )
        var presentation = KeyboardStageInteractionPresentation(state: pressed)
        let released = KeyboardStageInteractionState(
            pressedKeyCodes: [],
            heldKeyCodes: [],
            phase: .release,
            revision: 2
        )

        presentation.retarget(to: released, at: 10, reduceMotion: false)

        XCTAssertTrue(presentation.isAnimating)
        XCTAssertEqual(
            presentation.remainingDuration(at: 10),
            KeyboardStageInteractionPresentation.releaseDuration,
            accuracy: 0.001
        )
        XCTAssertEqual(presentation.levels(at: 10).pressed[57], 1)
        let middleLevel = try? XCTUnwrap(
            presentation.levels(at: 10.06).pressed[57]
        )
        XCTAssertGreaterThan(middleLevel ?? 0, 0)
        XCTAssertLessThan(middleLevel ?? 1, 1)
        XCTAssertNil(presentation.levels(at: 10.12).pressed[57])
    }

    func testReducedMotionReleaseSettlesWithoutSpatialAnimation() {
        let pressed = KeyboardStageInteractionState(
            pressedKeyCodes: [57],
            heldKeyCodes: [],
            phase: .press,
            revision: 1
        )
        var presentation = KeyboardStageInteractionPresentation(state: pressed)

        presentation.retarget(to: .idle, at: 10, reduceMotion: true)

        XCTAssertFalse(presentation.isAnimating)
        XCTAssertEqual(presentation.levels(at: 10), .idle)
    }

    func testTimelineRunsOnlyForBoundedMotion() {
        XCTAssertFalse(
            KeyboardStageTimelinePolicy.shouldPause(
                isAnimating: true
            )
        )
        XCTAssertTrue(
            KeyboardStageTimelinePolicy.shouldPause(
                isAnimating: false
            )
        )
    }
}
