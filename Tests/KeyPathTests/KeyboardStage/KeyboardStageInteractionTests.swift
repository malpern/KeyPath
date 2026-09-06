import AppKit
@testable import KeyPathAppKit
import XCTest

final class KeyboardStageInteractionTests: XCTestCase {
    /// The Metal view must stay transparent to the mouse. It is a real NSView,
    /// so without this it returns itself for every point inside the keyboard
    /// and swallows clicks before the semantic overlay's per-key hit targets
    /// receive them — pointer presses then work only in the SwiftUI fallback.
    @MainActor
    func testMetalStageViewPassesPointerEventsToTheOverlayAbove() {
        let view = KeyboardStageMTKView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300)
        )

        XCTAssertNil(view.hitTest(NSPoint(x: 200, y: 150)))
        XCTAssertNil(view.hitTest(NSPoint(x: 1, y: 1)))
    }

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

    func testKeyReleaseRunsABoundedUnderdampedSpring() {
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
        // The spring overshoots: shortly before settling the level dips a
        // few percent below rest — the cap rebounding above its home — and
        // never beyond the bounded envelope.
        let reboundLevel = presentation.levels(at: 10.13).pressed[57] ?? 0
        XCTAssertLessThan(reboundLevel, 0)
        XCTAssertGreaterThan(reboundLevel, -0.04)
        // Fully settled after the transition window: no residual level.
        XCTAssertNil(
            presentation.levels(
                at: 10 + KeyboardStageInteractionPresentation.releaseDuration
            ).pressed[57]
        )
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
