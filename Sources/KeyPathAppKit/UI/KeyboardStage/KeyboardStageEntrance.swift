import Foundation
import Observation

struct KeyboardStageEntranceFrame: Equatable, Sendable {
    var progress: Float
    var reduceMotion: Bool

    init(progress: Float, reduceMotion: Bool) {
        self.progress = min(1, max(0, progress))
        self.reduceMotion = reduceMotion
    }

    static let settled = KeyboardStageEntranceFrame(progress: 1, reduceMotion: false)

    var easedProgress: Float {
        KeyboardStageTransition.criticallyDampedProgress(progress)
    }

    var backdropDarkness: Double {
        let maximumDarkness: Float = reduceMotion ? 0.035 : 0.065
        return Double(maximumDarkness * (1 - easedProgress))
    }
}

struct KeyboardStageCinematicLighting: Equatable, Sendable {
    /// The light enters from the keyboard/right edge. Each surface still uses
    /// a critically damped response; only its start time changes across x.
    static let maximumDirectionalDelay: Float = 0.62

    static func exposure(
        for entrance: KeyboardStageEntranceFrame,
        normalizedX: Float
    ) -> Float {
        guard !entrance.reduceMotion else { return entrance.easedProgress }
        let x = min(1, max(0, normalizedX))
        let delay = (1 - x) * maximumDirectionalDelay
        let availableDuration = max(0.001, 1 - delay)
        let localProgress = (entrance.progress - delay) / availableDuration
        return KeyboardStageTransition.criticallyDampedProgress(localProgress)
    }

    static func normalizedX(
        for point: KeyboardStagePoint,
        in bounds: KeyboardStageRect
    ) -> Float {
        guard bounds.size.width > 0 else { return 0.5 }
        return min(1, max(0, (point.x - bounds.minX) / bounds.size.width))
    }
}

struct KeyboardStagePresentedFrame: Equatable, Sendable {
    var scene: KeyboardStageScene
    var entrance: KeyboardStageEntranceFrame
}

struct KeyboardStageSurfaceLighting: Equatable, Sendable {
    var illumination: Float
    var transientGlow: Float
    var shadowStrength: Float
    var legendOpacity: Float
    var legendTransitionProgress: Float
    var legendGlow: Float

    static let settled = KeyboardStageSurfaceLighting(
        illumination: 1,
        transientGlow: 0,
        shadowStrength: 1,
        legendOpacity: 1,
        legendTransitionProgress: 1,
        legendGlow: 0
    )

    func legendColor(settledColor: KeyboardStageRGBA) -> KeyboardStageRGBA {
        KeyboardStageRGBA(0.86, 0.93, 1)
            .interpolated(to: settledColor, progress: legendTransitionProgress)
    }
}

struct KeyboardStageLightingResolver: Equatable, Sendable {
    private enum SurfaceKind {
        case deck
        case key
        case decoration
    }

    private let scene: KeyboardStageScene
    private let entrance: KeyboardStageEntranceFrame

    init(scene: KeyboardStageScene, entrance: KeyboardStageEntranceFrame) {
        self.scene = scene
        self.entrance = entrance
    }

    func lighting(for key: KeyboardStageKey) -> KeyboardStageSurfaceLighting {
        resolve(at: key.frame.center, kind: .key)
    }

    func lighting(for decoration: KeyboardStageDecoration) -> KeyboardStageSurfaceLighting {
        resolve(
            at: decoration.frame.center,
            kind: decoration.kind == .keyboardDeck ? .deck : .decoration
        )
    }

    private func resolve(
        at point: KeyboardStagePoint,
        kind: SurfaceKind
    ) -> KeyboardStageSurfaceLighting {
        guard entrance.progress < 1 else { return .settled }

        let exposure: Float = if kind == .deck, !entrance.reduceMotion {
            // The deck is one large render surface, so use the average light
            // reaching its left, middle, and right regions. This keeps it
            // subordinate to the individually lit keycaps without leaving the
            // first illuminated keys floating over a completely black base.
            [Float(0.24), 0.52, 0.80]
                .map {
                    KeyboardStageCinematicLighting.exposure(
                        for: entrance,
                        normalizedX: $0
                    )
                }
                .reduce(0, +) / 3
        } else {
            KeyboardStageCinematicLighting.exposure(
                for: entrance,
                normalizedX: KeyboardStageCinematicLighting.normalizedX(
                    for: point,
                    in: scene.layoutBounds
                )
            )
        }
        let initialIllumination: Float = switch kind {
        case .deck:
            0.03
        case .key, .decoration:
            0.018
        }
        let initialGlow: Float = if scene.displayMode.reduceTransparency {
            0
        } else if kind == .deck {
            0
        } else {
            entrance.reduceMotion ? 0.34 : 0.44
        }

        return KeyboardStageSurfaceLighting(
            illumination: Self.interpolate(initialIllumination, 1, exposure),
            transientGlow: initialGlow * (1 - exposure),
            shadowStrength: entrance.reduceMotion
                ? 1
                : Self.interpolate(
                    kind == .deck ? 1.55 : 1.34,
                    1,
                    exposure
                ),
            legendOpacity: 1,
            legendTransitionProgress: exposure,
            legendGlow: scene.displayMode.reduceTransparency
                ? 0
                : 0.38 * (1 - exposure)
        )
    }

    private static func interpolate(_ start: Float, _ end: Float, _ progress: Float) -> Float {
        start + (end - start) * progress
    }
}

struct KeyboardStageEntrancePresentation: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case pending
        case holding(startedAt: TimeInterval, reduceMotion: Bool)
        case transitioning(startedAt: TimeInterval, duration: TimeInterval, reduceMotion: Bool)
        case settled
    }

    static let holdDuration: TimeInterval = 1.50
    static let transitionDuration: TimeInterval = 0.55
    static let reducedMotionTransitionDuration: TimeInterval = 0.25

    private(set) var phase = Phase.pending
    private(set) var revision = 0

    var isPending: Bool {
        phase == .pending
    }

    var isAnimating: Bool {
        if case .transitioning = phase { return true }
        return false
    }

    var hasPendingWork: Bool {
        switch phase {
        case .holding, .transitioning:
            true
        case .pending, .settled:
            false
        }
    }

    var isSettled: Bool {
        phase == .settled
    }

    var startedAt: TimeInterval? {
        switch phase {
        case let .holding(startedAt, _), let .transitioning(startedAt, _, _):
            startedAt
        case .pending, .settled:
            nil
        }
    }

    mutating func beginIfNeeded(at time: TimeInterval, reduceMotion: Bool) {
        guard phase == .pending else { return }
        phase = .holding(startedAt: time, reduceMotion: reduceMotion)
        revision &+= 1
    }

    func frame(at time: TimeInterval, pendingReduceMotion: Bool) -> KeyboardStageEntranceFrame {
        switch phase {
        case .pending:
            KeyboardStageEntranceFrame(progress: 0, reduceMotion: pendingReduceMotion)
        case let .holding(_, reduceMotion):
            KeyboardStageEntranceFrame(progress: 0, reduceMotion: reduceMotion)
        case let .transitioning(startedAt, duration, reduceMotion):
            KeyboardStageEntranceFrame(
                progress: duration > 0 ? Float((time - startedAt) / duration) : 1,
                reduceMotion: reduceMotion
            )
        case .settled:
            .settled
        }
    }

    func remainingDuration(at time: TimeInterval) -> TimeInterval {
        switch phase {
        case let .holding(startedAt, _):
            max(0, startedAt + Self.holdDuration - time)
        case let .transitioning(startedAt, duration, _):
            max(0, startedAt + duration - time)
        case .pending, .settled:
            0
        }
    }

    mutating func advance(at time: TimeInterval) {
        switch phase {
        case let .holding(startedAt, reduceMotion):
            let transitionStartedAt = startedAt + Self.holdDuration
            guard time >= transitionStartedAt else { return }
            let duration = reduceMotion
                ? Self.reducedMotionTransitionDuration
                : Self.transitionDuration
            if time >= transitionStartedAt + duration {
                settle()
                return
            }
            phase = .transitioning(
                startedAt: transitionStartedAt,
                duration: duration,
                reduceMotion: reduceMotion
            )
            revision &+= 1
        case let .transitioning(startedAt, duration, _):
            guard time >= startedAt + duration else { return }
            settle()
        case .pending, .settled:
            break
        }
    }

    mutating func settle() {
        guard phase != .settled else { return }
        phase = .settled
        revision &+= 1
    }
}

@MainActor
@Observable
final class KeyboardStageEntranceController {
    private(set) var presentation = KeyboardStageEntrancePresentation()

    func firstVisibleFramePresented(at time: TimeInterval, reduceMotion: Bool) {
        presentation.beginIfNeeded(at: time, reduceMotion: reduceMotion)
    }

    func settle() {
        presentation.settle()
    }

    func advance(at time: TimeInterval) {
        presentation.advance(at: time)
    }
}

struct KeyboardStageFrameInvalidation: Equatable, Sendable {
    private(set) var lastFrame: KeyboardStagePresentedFrame?

    mutating func begin(with frame: KeyboardStagePresentedFrame) {
        lastFrame = frame
    }

    mutating func shouldDraw(_ frame: KeyboardStagePresentedFrame) -> Bool {
        guard frame != lastFrame else { return false }
        lastFrame = frame
        return true
    }

    mutating func reset() {
        lastFrame = nil
    }
}

struct KeyboardStageFirstFrameGate: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var claimedGeneration: UInt64?

    mutating func beginGeneration() -> UInt64 {
        generation &+= 1
        claimedGeneration = nil
        return generation
    }

    mutating func invalidate() {
        generation &+= 1
        claimedGeneration = nil
    }

    mutating func claim(_ candidate: UInt64) -> Bool {
        guard candidate == generation,
              claimedGeneration != candidate
        else {
            return false
        }
        claimedGeneration = candidate
        return true
    }
}
