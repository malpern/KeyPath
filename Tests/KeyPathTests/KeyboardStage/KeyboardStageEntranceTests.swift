@testable import KeyPathAppKit
import XCTest

final class KeyboardStageEntranceTests: XCTestCase {
    func testEntranceHoldsStillForOnePointFiveSecondsThenTransitionsOnce() {
        var presentation = KeyboardStageEntrancePresentation()

        XCTAssertTrue(presentation.isPending)
        XCTAssertFalse(presentation.hasPendingWork)
        XCTAssertEqual(
            presentation.frame(at: 10, pendingReduceMotion: false).progress,
            0
        )

        presentation.beginIfNeeded(at: 10, reduceMotion: false)
        let revision = presentation.revision
        presentation.beginIfNeeded(at: 10.1, reduceMotion: false)

        XCTAssertEqual(presentation.startedAt, 10)
        XCTAssertEqual(presentation.revision, revision)
        XCTAssertTrue(presentation.hasPendingWork)
        XCTAssertFalse(presentation.isAnimating)
        XCTAssertEqual(
            presentation.frame(at: 11.99, pendingReduceMotion: false).progress,
            0
        )
        XCTAssertEqual(presentation.remainingDuration(at: 10), 2.0, accuracy: 0.001)

        presentation.advance(at: 11.99)
        XCTAssertEqual(presentation.revision, revision)
        XCTAssertFalse(presentation.isAnimating)

        presentation.advance(at: 12.0)
        XCTAssertTrue(presentation.isAnimating)
        XCTAssertEqual(presentation.startedAt, 12.0)
        XCTAssertEqual(
            presentation.frame(at: 12.375, pendingReduceMotion: false).progress,
            0.5,
            accuracy: 0.001
        )

        presentation.advance(at: 12.5)
        XCTAssertTrue(presentation.isAnimating)
        presentation.advance(at: 12.751)

        presentation.beginIfNeeded(at: 20, reduceMotion: false)

        XCTAssertTrue(presentation.isSettled)
        XCTAssertFalse(presentation.isAnimating)
        XCTAssertEqual(
            presentation.frame(at: 20, pendingReduceMotion: false),
            .settled
        )
    }

    func testPrePresentationTeardownCannotConsumeTheEntrance() {
        var presentation = KeyboardStageEntrancePresentation()

        presentation.settle()

        XCTAssertTrue(presentation.isPending)
        XCTAssertEqual(presentation.revision, 0)

        presentation.beginIfNeeded(at: 10, reduceMotion: false)

        XCTAssertEqual(presentation.startedAt, 10)
        XCTAssertEqual(
            presentation.frame(at: 11.99, pendingReduceMotion: false).progress,
            0
        )
        XCTAssertEqual(presentation.remainingDuration(at: 10), 2.0, accuracy: 0.001)
    }

    func testRegularEntranceUsesDirectionalGraphiteSurfacesAndBacklitLegends() throws {
        let scene = makeScene()
        let initial = KeyboardStageLightingResolver(
            scene: scene,
            entrance: KeyboardStageEntranceFrame(progress: 0, reduceMotion: false)
        )
        let middle = KeyboardStageLightingResolver(
            scene: scene,
            entrance: KeyboardStageEntranceFrame(progress: 0.5, reduceMotion: false)
        )
        let settled = KeyboardStageLightingResolver(
            scene: scene,
            entrance: .settled
        )
        let caps = try XCTUnwrap(scene.keys.first(where: { $0.keyCode == 57 }))
        let farKey = try XCTUnwrap(scene.keys.first(where: { $0.keyCode == 18 }))
        let deck = try XCTUnwrap(scene.decorations.first)
        var emphasizedCaps = caps
        emphasizedCaps.glow = 0.72

        XCTAssertEqual(initial.lighting(for: caps).illumination, 0.018, accuracy: 0.001)
        XCTAssertEqual(
            initial.lighting(for: caps).illumination,
            initial.lighting(for: farKey).illumination,
            accuracy: 0.001
        )
        XCTAssertEqual(initial.lighting(for: deck).illumination, 0.03, accuracy: 0.001)
        XCTAssertGreaterThan(initial.lighting(for: caps).shadowStrength, 1)
        XCTAssertEqual(initial.lighting(for: caps).legendOpacity, 1, accuracy: 0.001)
        XCTAssertEqual(initial.lighting(for: caps).legendTransitionProgress, 0, accuracy: 0.001)
        XCTAssertGreaterThan(initial.lighting(for: caps).legendGlow, 0)
        XCTAssertGreaterThan(
            initial.lighting(for: emphasizedCaps).legendGlow,
            initial.lighting(for: caps).legendGlow * 4
        )
        XCTAssertGreaterThan(
            middle.lighting(for: farKey).illumination,
            middle.lighting(for: caps).illumination
        )
        XCTAssertGreaterThan(middle.lighting(for: deck).illumination, 0.03)
        XCTAssertLessThan(
            middle.lighting(for: deck).illumination,
            middle.lighting(for: farKey).illumination
        )
        XCTAssertGreaterThan(middle.lighting(for: caps).transientGlow, 0)
        XCTAssertEqual(middle.lighting(for: caps).legendTransitionProgress, 0)
        XCTAssertGreaterThan(middle.lighting(for: farKey).legendTransitionProgress, 0)
        // The eased front dwells on the keyboard, so the far key completes its
        // legend transition later than the linear halfway point.
        let late = KeyboardStageLightingResolver(
            scene: scene,
            entrance: KeyboardStageEntranceFrame(progress: 0.8, reduceMotion: false)
        )
        XCTAssertEqual(
            late.lighting(for: farKey).legendTransitionProgress,
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(settled.lighting(for: caps), .settled)
        XCTAssertEqual(settled.lighting(for: emphasizedCaps), .settled)
        XCTAssertEqual(settled.lighting(for: farKey), .settled)
        XCTAssertEqual(settled.lighting(for: deck), .settled)
    }

    func testCinematicLightEntersFromTheKeyboardSide() {
        let entrance = KeyboardStageEntranceFrame(progress: 0.3, reduceMotion: false)
        let left = KeyboardStageCinematicLighting.exposure(
            for: entrance,
            normalizedX: 0
        )
        let right = KeyboardStageCinematicLighting.exposure(
            for: entrance,
            normalizedX: 1
        )

        XCTAssertGreaterThan(right, left)
        XCTAssertEqual(
            KeyboardStageCinematicLighting.exposure(
                for: KeyboardStageEntranceFrame(progress: 0, reduceMotion: false),
                normalizedX: 1
            ),
            0
        )
        XCTAssertEqual(
            KeyboardStageCinematicLighting.exposure(
                for: .settled,
                normalizedX: 0
            ),
            1
        )

        let nearlySettled = KeyboardStageEntranceFrame(
            progress: 0.99,
            reduceMotion: false
        )
        XCTAssertEqual(
            KeyboardStageCinematicLighting.exposure(
                for: nearlySettled,
                normalizedX: 0
            ),
            1,
            accuracy: 0.001
        )

        // The eased front dwells on the keyboard, so it reaches mid-window
        // later than the linear halfway point.
        let crossing = KeyboardStageEntranceFrame(progress: 0.62, reduceMotion: false)
        XCTAssertGreaterThan(
            KeyboardStageCinematicLighting.exposure(
                for: crossing,
                normalizedX: 0.5,
                normalizedY: 0
            ),
            KeyboardStageCinematicLighting.exposure(
                for: crossing,
                normalizedX: 0.5,
                normalizedY: 1
            )
        )
    }

    func testCinematicLightingParametersAreTheSharedGPUContract() {
        let start = KeyboardStageCinematicLighting.parameters(
            for: KeyboardStageEntranceFrame(progress: 0, reduceMotion: false)
        )
        let middle = KeyboardStageCinematicLighting.parameters(
            for: KeyboardStageEntranceFrame(progress: 0.5, reduceMotion: false)
        )
        let end = KeyboardStageCinematicLighting.parameters(for: .settled)

        XCTAssertEqual(start.frontX, 1.08, accuracy: 0.001)
        // Ease-in travel: at half progress the front is still over the
        // keyboard span rather than at the linear midpoint of 0.31.
        XCTAssertEqual(middle.frontX, 0.6674, accuracy: 0.001)
        XCTAssertEqual(end.frontX, -0.46, accuracy: 0.001)
        XCTAssertEqual(end.feather, 0.40, accuracy: 0.001)
        XCTAssertEqual(end.verticalSkew, 0.06, accuracy: 0.001)
        XCTAssertEqual(end.gpuVector.x, -0.46, accuracy: 0.001)
        XCTAssertEqual(end.gpuVector.y, 0.40, accuracy: 0.001)
        XCTAssertEqual(end.gpuVector.z, 0.06, accuracy: 0.001)
        XCTAssertEqual(end.gpuVector.w, 0, accuracy: 0.001)
    }

    func testNativeFallbackMapsTheHeroIntoWindowSpaceLikeMetal() throws {
        let scene = makeScene()
        let projection = KeyboardStageProjection(
            scene: scene,
            size: CGSize(width: 600, height: 420)
        )
        let entrance = KeyboardStageEntranceFrame(progress: 0.5, reduceMotion: false)
        let windowX = SIMD2<Float>(0.42, 0.56)
        let resolver = KeyboardStageLightingResolver(
            scene: scene,
            entrance: entrance,
            projection: projection,
            windowX: windowX
        )
        let caps = try XCTUnwrap(scene.keys.first(where: { $0.keyCode == 57 }))
        let projectedCenter = projection.project(caps.frame.center)
        let localX = min(
            1,
            max(0, Float(projectedCenter.x) / projection.destinationSize.width)
        )
        let localY = min(
            1,
            max(0, Float(projectedCenter.y) / projection.destinationSize.height)
        )
        let expectedExposure = KeyboardStageCinematicLighting.exposure(
            for: entrance,
            normalizedX: windowX.x + localX * windowX.y,
            normalizedY: localY
        )
        let expectedIllumination = 0.018 + (1 - 0.018) * expectedExposure

        XCTAssertEqual(
            resolver.lighting(for: caps).illumination,
            expectedIllumination,
            accuracy: 0.001
        )
    }

    func testReducedMotionKeepsStaticBacklightAndUsesOnlyAUniformColorResolve() throws {
        var scene = makeScene()
        scene.displayMode.reduceMotion = true
        let entrance = KeyboardStageEntranceFrame(progress: 0.35, reduceMotion: true)
        let resolver = KeyboardStageLightingResolver(scene: scene, entrance: entrance)
        let caps = try XCTUnwrap(scene.keys.first(where: { $0.keyCode == 57 }))
        let farKey = try XCTUnwrap(scene.keys.first(where: { $0.keyCode == 18 }))
        let capsLighting = resolver.lighting(for: caps)
        let farLighting = resolver.lighting(for: farKey)

        XCTAssertEqual(capsLighting.illumination, farLighting.illumination, accuracy: 0.001)
        XCTAssertEqual(capsLighting.legendOpacity, farLighting.legendOpacity, accuracy: 0.001)
        XCTAssertGreaterThan(capsLighting.transientGlow, 0)
        XCTAssertEqual(capsLighting.shadowStrength, 1)
        XCTAssertGreaterThan(capsLighting.illumination, 0.5)
        XCTAssertLessThan(capsLighting.illumination, 1)
    }

    func testReducedMotionPreservesTheHoldAndShortensOnlyTheColorTransition() {
        var presentation = KeyboardStageEntrancePresentation()

        presentation.beginIfNeeded(at: 5, reduceMotion: true)
        XCTAssertEqual(presentation.remainingDuration(at: 5), 2.0, accuracy: 0.001)
        XCTAssertEqual(
            presentation.frame(at: 6.99, pendingReduceMotion: false).progress,
            0
        )

        presentation.advance(at: 7.0)
        XCTAssertTrue(presentation.isAnimating)
        XCTAssertEqual(presentation.remainingDuration(at: 7.0), 0.25, accuracy: 0.001)
        XCTAssertTrue(
            presentation.frame(at: 7.125, pendingReduceMotion: false).reduceMotion
        )
    }

    func testLateWakeKeepsTheOriginalLightRiseDeadline() {
        var presentation = KeyboardStageEntrancePresentation()

        presentation.beginIfNeeded(at: 10, reduceMotion: false)
        presentation.advance(at: 12.25)

        XCTAssertTrue(presentation.isAnimating)
        XCTAssertEqual(presentation.startedAt, 12.0)
        XCTAssertEqual(
            presentation.frame(at: 12.25, pendingReduceMotion: false).progress,
            Float(0.25 / 0.75),
            accuracy: 0.001
        )

        var veryLatePresentation = KeyboardStageEntrancePresentation()
        veryLatePresentation.beginIfNeeded(at: 10, reduceMotion: false)
        veryLatePresentation.advance(at: 12.8)
        XCTAssertTrue(veryLatePresentation.isSettled)
    }

    func testReducedTransparencyRemovesKeyAndLegendHalos() throws {
        var scene = makeScene()
        scene.displayMode.reduceTransparency = true
        let resolver = KeyboardStageLightingResolver(
            scene: scene,
            entrance: KeyboardStageEntranceFrame(progress: 0, reduceMotion: false)
        )
        let caps = try XCTUnwrap(scene.keys.first)
        let lighting = resolver.lighting(for: caps)

        XCTAssertEqual(lighting.transientGlow, 0)
        XCTAssertEqual(lighting.legendGlow, 0)
        XCTAssertEqual(lighting.legendOpacity, 1)
    }

    func testDialogPaletteResolvesFromDarkRoomToExactReferenceLightColors() {
        let dark = FirstSuccessOnboardingPalette.resolve(
            ambientLight: 0,
            increaseContrast: false
        )
        let beforeContrastPivot = FirstSuccessOnboardingPalette.resolve(
            ambientLight: 0.49,
            increaseContrast: false
        )
        let afterContrastPivot = FirstSuccessOnboardingPalette.resolve(
            ambientLight: 0.50,
            increaseContrast: false
        )
        let light = FirstSuccessOnboardingPalette.resolve(
            ambientLight: 1,
            increaseContrast: false
        )

        XCTAssertEqual(dark, .dark)
        XCTAssertEqual(
            beforeContrastPivot.primaryText,
            FirstSuccessOnboardingPalette.dark.primaryText
        )
        XCTAssertEqual(
            afterContrastPivot.primaryText,
            FirstSuccessOnboardingPalette.light.primaryText
        )
        XCTAssertEqual(light, .light)
        XCTAssertEqual(light.backgroundLeading, FirstSuccessOnboardingColor(244, 243, 243))
        XCTAssertEqual(light.backgroundTrailing, FirstSuccessOnboardingColor(247, 246, 246))
        XCTAssertEqual(light.primaryText, FirstSuccessOnboardingColor(43, 42, 42))
        XCTAssertEqual(light.accent, FirstSuccessOnboardingColor(37, 127, 254))
    }

    func testFrameInvalidationDrawsOnlyChangedPresentedFrames() {
        let first = KeyboardStagePresentedFrame(
            scene: makeScene(),
            entrance: KeyboardStageEntranceFrame(progress: 0, reduceMotion: false)
        )
        var second = first
        second.entrance.progress = 0.5
        var invalidation = KeyboardStageFrameInvalidation()

        invalidation.begin(with: first)

        XCTAssertFalse(invalidation.shouldDraw(first))
        XCTAssertTrue(invalidation.shouldDraw(second))
        XCTAssertFalse(invalidation.shouldDraw(second))
        invalidation.reset()
        XCTAssertTrue(invalidation.shouldDraw(second))
    }

    func testFirstFrameGateRejectsDuplicateAndStaleRendererCallbacks() {
        var gate = KeyboardStageFirstFrameGate()
        let firstGeneration = gate.beginGeneration()

        XCTAssertTrue(gate.claim(firstGeneration))
        XCTAssertFalse(gate.claim(firstGeneration))

        let secondGeneration = gate.beginGeneration()
        XCTAssertFalse(gate.claim(firstGeneration))
        XCTAssertTrue(gate.claim(secondGeneration))

        gate.invalidate()
        XCTAssertFalse(gate.claim(secondGeneration))
    }

    private func makeScene() -> KeyboardStageScene {
        let bounds = KeyboardStageRect(x: 0, y: 0, width: 12, height: 4)
        return KeyboardStageScene(
            layoutID: "entrance-test",
            layoutBounds: bounds,
            viewport: KeyboardStageViewport(focus: bounds.center, zoom: 1, verticalBias: 0),
            keys: [
                makeKey(id: "caps", keyCode: 57, x: 0.5, y: 1.5),
                makeKey(id: "far", keyCode: 18, x: 10.5, y: 0.5),
            ],
            decorations: [
                KeyboardStageDecoration(
                    id: "deck",
                    kind: .keyboardDeck,
                    frame: bounds,
                    rotationRadians: 0,
                    role: .deck,
                    opacity: 1,
                    pressure: 0,
                    glow: 0,
                    scale: 1
                ),
            ],
            revealTarget: .none,
            displayMode: .standard,
            transitionDuration: 0.38
        )
    }

    private func makeKey(
        id: String,
        keyCode: UInt16,
        x: Float,
        y: Float
    ) -> KeyboardStageKey {
        KeyboardStageKey(
            id: id,
            keyCode: keyCode,
            frame: KeyboardStageRect(x: x, y: y, width: 1, height: 1),
            rotationRadians: 0,
            legend: KeyboardStageLegend(primary: id),
            role: .standard,
            opacity: 1,
            pressure: 0,
            glow: 0,
            interactionLevel: 0,
            scale: 1,
            translation: .zero,
            accessibilityRole: nil
        )
    }
}
