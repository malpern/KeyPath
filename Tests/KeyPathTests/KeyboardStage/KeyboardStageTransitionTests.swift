@testable import KeyPathAppKit
import XCTest

final class KeyboardStageTransitionTests: XCTestCase {
    func testCriticallyDampedProgressHasExactEndpoints() {
        XCTAssertEqual(KeyboardStageTransition.criticallyDampedProgress(-1), 0)
        XCTAssertEqual(KeyboardStageTransition.criticallyDampedProgress(0), 0)
        XCTAssertEqual(KeyboardStageTransition.criticallyDampedProgress(1), 1)
        XCTAssertEqual(KeyboardStageTransition.criticallyDampedProgress(2), 1)
        XCTAssertGreaterThan(KeyboardStageTransition.criticallyDampedProgress(0.5), 0.5)
    }

    func testInterruptedTransitionStartsFromTheCurrentlyPresentedScene() {
        let first = scene(role: .standard, primary: "Caps")
        let second = scene(role: .escape, primary: "Esc")
        let third = scene(role: .hyper, primary: "Hyper")
        var presentation = KeyboardStagePresentation(scene: first)

        presentation.retarget(to: second, at: 10, reduceMotion: false)
        let interruptedScene = presentation.scene(at: 10.1)
        presentation.retarget(to: third, at: 10.1, reduceMotion: false)

        XCTAssertEqual(presentation.transition?.start, interruptedScene)
        XCTAssertEqual(presentation.transition?.target, third)
    }

    func testReduceMotionSettlesWithoutAVisualTransition() {
        let first = scene(role: .standard, primary: "Caps")
        let second = scene(role: .escape, primary: "Esc")
        var presentation = KeyboardStagePresentation(scene: first)

        presentation.retarget(to: second, at: 10, reduceMotion: true)

        XCTAssertFalse(presentation.isAnimating)
        XCTAssertEqual(presentation.scene(at: 10), second)
    }

    func testTransformationProducesDistinctEarlyMiddleAndSettledFrames() {
        let first = scene(role: .standard, primary: "Caps")
        var second = scene(role: .escape, primary: "Esc")
        second.keys[0].scale = 0.78
        second.keys[0].translation = KeyboardStagePoint(x: -0.48, y: -0.52)
        second.keys[0].pressure = 0.8
        var presentation = KeyboardStagePresentation(scene: first)

        presentation.retarget(to: second, at: 10, reduceMotion: false)
        let early = presentation.scene(at: 10.03).keys[0]
        let middle = presentation.scene(at: 10.19).keys[0]
        let settled = presentation.scene(at: 10.38).keys[0]

        XCTAssertNotEqual(early.transformedFrame, middle.transformedFrame)
        XCTAssertNotEqual(middle.transformedFrame, settled.transformedFrame)
        XCTAssertGreaterThan(middle.pressure, early.pressure)
        XCTAssertEqual(settled, second.keys[0])
    }

    private func scene(
        role: KeyboardStageKeyRole,
        primary: String
    ) -> KeyboardStageScene {
        let bounds = KeyboardStageRect(x: 0, y: 0, width: 4, height: 2)
        return KeyboardStageScene(
            layoutID: "transition-test",
            layoutBounds: bounds,
            viewport: KeyboardStageViewport(focus: bounds.center, zoom: 1, verticalBias: 0),
            keys: [
                KeyboardStageKey(
                    id: "caps",
                    keyCode: 57,
                    frame: KeyboardStageRect(x: 0, y: 0, width: 1.5, height: 1),
                    rotationRadians: 0,
                    legend: KeyboardStageLegend(primary: primary),
                    role: role,
                    opacity: 1,
                    pressure: 0,
                    glow: 0,
                    scale: 1,
                    translation: .zero,
                    accessibilityRole: nil
                ),
            ],
            decorations: [],
            revealTarget: .none,
            displayMode: .standard,
            transitionDuration: 0.38
        )
    }
}
