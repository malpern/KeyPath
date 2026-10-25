@testable import KeyPathAppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Deterministic native-fallback coverage for the visual states that feed both
/// the SwiftUI and Metal keyboard-stage renderers.
@MainActor
final class FirstSuccessOnboardingSnapshotTests: ScreenshotTestCase {
    func testDarkRoomEntrance() {
        assertStage(
            moment: .capsMotivation,
            entrance: KeyboardStageEntranceFrame(progress: 0, reduceMotion: false),
            named: "first-success-dark-room"
        )
    }

    func testDirectionalLightTransition() {
        assertStage(
            moment: .capsMotivation,
            entrance: KeyboardStageEntranceFrame(progress: 0.5, reduceMotion: false),
            named: "first-success-directional-light"
        )
    }

    func testCapsLockInstalled() {
        assertStage(moment: .capsInstalled, named: "first-success-caps-installed")
    }

    func testHyperInstalled() {
        assertStage(moment: .hyperInstalled, named: "first-success-hyper-installed")
    }

    func testLauncherChoice() {
        assertStage(moment: .launcher, named: "first-success-launcher-choice")
    }

    func testRulesHandoff() {
        assertStage(moment: .handoff, named: "first-success-rules-handoff")
    }

    func testReducedMotionResolve() {
        assertStage(
            moment: .capsInstalled,
            displayMode: KeyboardStageDisplayMode(
                reduceMotion: true,
                reduceTransparency: false,
                increaseContrast: false
            ),
            entrance: KeyboardStageEntranceFrame(progress: 0.5, reduceMotion: true),
            named: "first-success-reduced-motion"
        )
    }

    private func assertStage(
        moment: KeyboardStageMoment,
        displayMode: KeyboardStageDisplayMode = .standard,
        entrance: KeyboardStageEntranceFrame = .settled,
        named name: String
    ) {
        let scene = KeyboardStageSceneBuilder.make(
            layout: .macBookUS,
            keymap: .qwertyUS,
            moment: moment,
            displayMode: displayMode
        )
        let frame = KeyboardStagePresentedFrame(scene: scene, entrance: entrance)

        assertScreenshot(
            of: KeyboardStageSnapshotView(frame: frame),
            size: SnapshotSize.onboardingHero,
            named: name,
            precision: 0.99,
            perceptualPrecision: 0.98
        )
    }
}

private struct KeyboardStageSnapshotView: View {
    let frame: KeyboardStagePresentedFrame

    var body: some View {
        ZStack {
            KeyboardStageBackdrop(
                displayMode: frame.scene.displayMode,
                entrance: frame.entrance
            )
            SwiftUIKeyboardStageView(frame: frame)
            KeyboardStageSemanticOverlay(frame: frame) { _, _ in }
        }
        .background(Color(red: 0.968, green: 0.964, blue: 0.956))
    }
}
