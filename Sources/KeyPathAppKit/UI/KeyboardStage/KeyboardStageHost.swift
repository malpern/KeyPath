import KeyPathCore
import Observation
import SwiftUI

struct KeyboardStageHost: View {
    let scene: KeyboardStageScene
    let interaction: KeyboardStageInteractionState
    let renderer: KeyboardStageRendererPreference
    let entrance: KeyboardStageEntranceController

    private let clock: any KeyboardStageClock

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var presentation: KeyboardStagePresentation
    @State private var interactionPresentation: KeyboardStageInteractionPresentation
    @State private var pointerPressedKeyCodes: Set<UInt16> = []
    @State private var pointerInteractionPhase = KeyboardStageInteractionPhase.idle
    @State private var pointerInteractionRevision: UInt64 = 0
    @State private var metalFailure = KeyboardStageMetalFailureState()

    init(
        scene: KeyboardStageScene,
        interaction: KeyboardStageInteractionState = .idle,
        renderer: KeyboardStageRendererPreference = .automatic,
        entrance: KeyboardStageEntranceController,
        clock: any KeyboardStageClock = SystemKeyboardStageClock()
    ) {
        self.scene = scene
        self.interaction = interaction
        self.renderer = renderer
        self.entrance = entrance
        self.clock = clock
        _presentation = State(initialValue: KeyboardStagePresentation(scene: scene))
        _interactionPresentation = State(
            initialValue: KeyboardStageInteractionPresentation(state: interaction)
        )
    }

    var body: some View {
        TimelineView(.animation(paused: timelinePaused)) { _ in
            let time = clock.now()
            let baseScene = effectiveReduceMotion
                ? scene
                : presentation.scene(at: time)
            let presentedScene = baseScene
                .replacingDisplayMode(environmentDisplayMode)
                .applyingInteraction(interactionPresentation.levels(at: time))
            let presentedFrame = KeyboardStagePresentedFrame(
                scene: presentedScene,
                entrance: entrance.presentation.frame(
                    at: time,
                    pendingReduceMotion: effectiveReduceMotion
                )
            )
            KeyboardStageRenderedContent(
                frame: presentedFrame,
                renderer: KeyboardStageRendererPolicy.effectivePreference(requested: renderer),
                metalFailure: metalFailure,
                onPointerPressChange: updatePointerPress,
                onFirstFramePresented: beginEntrance
            )
        }
        .onChange(of: scene) { _, newScene in
            presentation.retarget(
                to: newScene,
                at: clock.now(),
                reduceMotion: effectiveReduceMotion
            )
        }
        .onChange(of: interaction) { _, newInteraction in
            interactionPresentation.retarget(
                to: mergedInteraction(
                    external: newInteraction,
                    eventPhase: newInteraction.phase
                ),
                at: clock.now(),
                reduceMotion: effectiveReduceMotion
            )
        }
        .onChange(of: effectiveReduceMotion) { _, shouldReduceMotion in
            guard shouldReduceMotion else { return }
            if entrance.presentation.hasPendingWork {
                entrance.settle()
            }
            presentation.settle(on: scene)
            interactionPresentation.settle(
                on: KeyboardStageInteractionLevels(state: effectiveInteraction)
            )
        }
        .task(id: presentation.revision) {
            guard presentation.isAnimating else { return }
            let revision = presentation.revision
            let delay = presentation.remainingDuration(at: clock.now())
            if delay > 0 {
                try? await Task<Never, Never>.sleep(
                    for: .milliseconds(Int64((delay * 1000).rounded(.up)))
                )
            }
            guard !Task.isCancelled,
                  presentation.revision == revision
            else {
                return
            }
            presentation.settle()
        }
        .task(id: interactionPresentation.revision) {
            guard interactionPresentation.isAnimating else { return }
            let revision = interactionPresentation.revision
            let delay = interactionPresentation.remainingDuration(at: clock.now())
            if delay > 0 {
                try? await Task<Never, Never>.sleep(
                    for: .milliseconds(Int64((delay * 1000).rounded(.up)))
                )
            }
            guard !Task.isCancelled,
                  interactionPresentation.revision == revision
            else {
                return
            }
            interactionPresentation.settle()
        }
        .task(id: entrance.presentation.revision) {
            guard entrance.presentation.hasPendingWork else { return }
            let revision = entrance.presentation.revision
            let delay = entrance.presentation.remainingDuration(at: clock.now())
            if delay > 0 {
                try? await Task<Never, Never>.sleep(
                    for: .milliseconds(Int64((delay * 1000).rounded(.up)))
                )
            }
            guard !Task.isCancelled,
                  entrance.presentation.revision == revision
            else {
                return
            }
            entrance.advance(at: clock.now())
        }
        .onDisappear {
            pointerPressedKeyCodes.removeAll()
            pointerInteractionPhase = .idle
            pointerInteractionRevision &+= 1
            presentation.settle(on: scene)
            interactionPresentation.settle(
                on: KeyboardStageInteractionLevels(state: effectiveInteraction)
            )
        }
    }

    private var effectiveReduceMotion: Bool {
        reduceMotion || scene.displayMode.reduceMotion
    }

    private var effectiveInteraction: KeyboardStageInteractionState {
        mergedInteraction(
            external: interaction,
            eventPhase: interaction.phase
        )
    }

    private func mergedInteraction(
        external: KeyboardStageInteractionState,
        eventPhase: KeyboardStageInteractionPhase
    ) -> KeyboardStageInteractionState {
        KeyboardStageInteractionState(
            pressedKeyCodes: external.pressedKeyCodes.union(pointerPressedKeyCodes),
            heldKeyCodes: external.heldKeyCodes,
            phase: eventPhase,
            revision: external.revision &+ pointerInteractionRevision
        )
    }

    private var timelinePaused: Bool {
        KeyboardStageTimelinePolicy.shouldPause(
            isAnimating: presentation.isAnimating
                || interactionPresentation.isAnimating
                || entrance.presentation.isAnimating
        )
    }

    private var environmentDisplayMode: KeyboardStageDisplayMode {
        KeyboardStageDisplayMode(
            appearance: colorScheme == .dark ? .dark : .light,
            reduceMotion: effectiveReduceMotion,
            reduceTransparency: reduceTransparency || scene.displayMode.reduceTransparency,
            increaseContrast: colorSchemeContrast == .increased || scene.displayMode.increaseContrast,
            differentiateWithoutColor: differentiateWithoutColor
                || scene.displayMode.differentiateWithoutColor
        )
    }

    private func updatePointerPress(keyCode: UInt16, isPressed: Bool) {
        let changed: Bool
        if isPressed {
            changed = pointerPressedKeyCodes.insert(keyCode).inserted
            pointerInteractionPhase = .press
        } else {
            changed = pointerPressedKeyCodes.remove(keyCode) != nil
            pointerInteractionPhase = .release
        }
        guard changed else { return }
        pointerInteractionRevision &+= 1
        interactionPresentation.retarget(
            to: mergedInteraction(
                external: interaction,
                eventPhase: pointerInteractionPhase
            ),
            at: clock.now(),
            reduceMotion: effectiveReduceMotion
        )
    }

    private func beginEntrance() {
        entrance.firstVisibleFramePresented(
            at: clock.now(),
            reduceMotion: effectiveReduceMotion
        )
    }
}

enum KeyboardStageTimelinePolicy {
    static func shouldPause(isAnimating: Bool) -> Bool {
        !isAnimating
    }
}

@MainActor
@Observable
private final class KeyboardStageMetalFailureState {
    private(set) var failed = false
    private(set) var message: String?

    func record(_ error: Error) {
        failed = true
        message = error.localizedDescription
    }
}

private struct KeyboardStageRenderedContent: View {
    let frame: KeyboardStagePresentedFrame
    let renderer: KeyboardStageRendererPreference
    let metalFailure: KeyboardStageMetalFailureState
    let onPointerPressChange: @MainActor @Sendable (UInt16, Bool) -> Void
    let onFirstFramePresented: @MainActor @Sendable () -> Void

    var body: some View {
        let policy = KeyboardStageRendererPolicy(
            preference: renderer,
            displayMode: frame.scene.displayMode,
            metalAvailable: KeyboardStageMetalView.isSupported,
            metalFailed: metalFailure.failed
        )

        ZStack {
            KeyboardStageBackdrop(
                displayMode: frame.scene.displayMode,
                entrance: frame.entrance
            )

            switch policy.backend {
            case .metal:
                KeyboardStageMetalView(
                    frame: frame,
                    onFirstFramePresented: onFirstFramePresented
                ) { error in
                    metalFailure.record(error)
                }
                .accessibilityHidden(true)

            case .swiftUI:
                SwiftUIKeyboardStageView(frame: frame)
                    .background {
                        KeyboardStageNativeFirstFrameProbe(
                            onFirstFramePresented: onFirstFramePresented
                        )
                    }
            }

            KeyboardStageSemanticOverlay(
                frame: frame,
                rendersKeyLegends: policy.backend == .swiftUI,
                onPointerPressChange: onPointerPressChange
            )
        }
        .clipped()
    }
}

struct KeyboardStageBackdrop: View {
    let displayMode: KeyboardStageDisplayMode
    let entrance: KeyboardStageEntranceFrame

    var body: some View {
        let stageExposure = KeyboardStageCinematicLighting.exposure(
            for: entrance,
            normalizedX: 0.62
        )
        if displayMode.appearance == .light {
            RadialGradient(
                colors: [
                    Color.white.opacity(0.20 * Double(stageExposure)),
                    Color.clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: 420
            )
            .accessibilityHidden(true)
        } else {
            let palette = KeyboardStagePalette(displayMode: displayMode)
            LinearGradient(
                colors: displayMode.reduceTransparency
                    ? [palette.backgroundBottom.color, palette.backgroundBottom.color]
                    : [palette.backgroundTop.color, palette.backgroundBottom.color],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                RadialGradient(
                    colors: [Color.white.opacity(0.04), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 320
                )
            }
            .accessibilityHidden(true)
        }
        if !displayMode.reduceTransparency,
           entrance.backdropDarkness > 0
        {
            RadialGradient(
                colors: [
                    Color.black.opacity(entrance.backdropDarkness),
                    Color.black.opacity(entrance.backdropDarkness * 0.34),
                    Color.clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: 430
            )
            .accessibilityHidden(true)
        }
    }
}
