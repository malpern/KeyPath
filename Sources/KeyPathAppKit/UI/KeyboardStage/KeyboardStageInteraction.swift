import Foundation

enum KeyboardStageInteractionPhase: Equatable, Sendable {
    case idle
    case press
    case hold
    case release
}

struct KeyboardStageInteractionState: Equatable, Sendable {
    var pressedKeyCodes: Set<UInt16>
    var heldKeyCodes: Set<UInt16>
    var phase: KeyboardStageInteractionPhase
    var revision: UInt64

    static let idle = KeyboardStageInteractionState(
        pressedKeyCodes: [],
        heldKeyCodes: [],
        phase: .idle,
        revision: 0
    )
}

struct KeyboardStageInteractionLevels: Equatable, Sendable {
    var pressed: [UInt16: Float]
    var held: [UInt16: Float]

    static let idle = KeyboardStageInteractionLevels(pressed: [:], held: [:])

    init(state: KeyboardStageInteractionState) {
        pressed = Dictionary(uniqueKeysWithValues: state.pressedKeyCodes.map { ($0, 1) })
        held = Dictionary(uniqueKeysWithValues: state.heldKeyCodes.map { ($0, 1) })
    }

    init(pressed: [UInt16: Float], held: [UInt16: Float]) {
        self.pressed = pressed
        self.held = held
    }

    static func interpolated(
        from start: KeyboardStageInteractionLevels,
        to end: KeyboardStageInteractionLevels,
        progress: Float
    ) -> KeyboardStageInteractionLevels {
        KeyboardStageInteractionLevels(
            pressed: interpolate(start.pressed, end.pressed, progress: progress),
            held: interpolate(start.held, end.held, progress: progress)
        )
    }

    private static func interpolate(
        _ start: [UInt16: Float],
        _ end: [UInt16: Float],
        progress: Float
    ) -> [UInt16: Float] {
        let keyCodes = Set(start.keys).union(end.keys)
        return Dictionary(uniqueKeysWithValues: keyCodes.compactMap { keyCode in
            let level = (start[keyCode] ?? 0)
                + ((end[keyCode] ?? 0) - (start[keyCode] ?? 0)) * progress
            // Keep small negative levels: the release spring overshoots so
            // the cap rebounds a hair above rest before settling.
            guard abs(level) > 0.001 else { return nil }
            return (keyCode, level)
        })
    }
}

private struct KeyboardStageInteractionTransition: Equatable, Sendable {
    var start: KeyboardStageInteractionLevels
    var target: KeyboardStageInteractionLevels
    var startedAt: TimeInterval
    var duration: TimeInterval

    var endsAt: TimeInterval {
        startedAt + duration
    }

    func levels(at time: TimeInterval) -> KeyboardStageInteractionLevels {
        let linearProgress = duration > 0
            ? Float((time - startedAt) / duration)
            : 1
        return .interpolated(
            from: start,
            to: target,
            progress: KeyboardStageTransition.underdampedReleaseProgress(linearProgress)
        )
    }
}

struct KeyboardStageInteractionPresentation: Equatable, Sendable {
    static let releaseDuration: TimeInterval = 0.19

    private(set) var settledLevels: KeyboardStageInteractionLevels
    private(set) var revision: Int
    private var transition: KeyboardStageInteractionTransition?

    init(state: KeyboardStageInteractionState = .idle) {
        settledLevels = KeyboardStageInteractionLevels(state: state)
        revision = 0
    }

    var isAnimating: Bool {
        transition != nil
    }

    func levels(at time: TimeInterval) -> KeyboardStageInteractionLevels {
        transition?.levels(at: time) ?? settledLevels
    }

    func remainingDuration(at time: TimeInterval) -> TimeInterval {
        guard let transition else { return 0 }
        return max(0, transition.endsAt - time)
    }

    mutating func retarget(
        to state: KeyboardStageInteractionState,
        at time: TimeInterval,
        reduceMotion: Bool
    ) {
        let current = levels(at: time)
        let target = KeyboardStageInteractionLevels(state: state)
        guard current != target else {
            settle(on: target)
            return
        }

        revision &+= 1
        guard !reduceMotion, state.phase == .release else {
            settle(on: target)
            return
        }

        settledLevels = current
        transition = KeyboardStageInteractionTransition(
            start: current,
            target: target,
            startedAt: time,
            duration: Self.releaseDuration
        )
    }

    mutating func settle() {
        guard let transition else { return }
        settle(on: transition.target)
    }

    mutating func settle(on levels: KeyboardStageInteractionLevels) {
        settledLevels = levels
        transition = nil
        revision &+= 1
    }
}

extension KeyboardStageScene {
    func applyingInteraction(_ interaction: KeyboardStageInteractionLevels) -> KeyboardStageScene {
        var copy = self
        copy.keys = keys.map { key in
            let pressLevel = interaction.pressed[key.keyCode] ?? 0
            let holdLevel = interaction.held[key.keyCode] ?? 0
            let level = max(pressLevel, holdLevel)
            guard abs(level) > 0.001 else { return key }

            var responsiveKey = key
            responsiveKey.opacity = max(responsiveKey.opacity, 0.98)
            responsiveKey.interactionLevel = max(0, level)
            let positivePress = max(0, pressLevel)
            let positiveHold = max(0, holdLevel)
            // The sub-linear press term makes the glow linger behind the
            // mechanical release — a short phosphor tail that reads as
            // "registered" without adding an event.
            responsiveKey.glow = max(
                responsiveKey.glow,
                0.72 * pow(positivePress, 0.55) + 0.22 * positiveHold
            )

            guard !displayMode.reduceMotion else { return responsiveKey }
            responsiveKey.pressure = max(
                responsiveKey.pressure,
                0.88 * positivePress + 0.10 * positiveHold
            )
            // A press travels: the cap moves down inside its fixed well (and
            // the signed spring level lets it rebound just above rest). The
            // footprint never shrinks.
            responsiveKey.translation.y += 0.020 * pressLevel + 0.004 * positiveHold
            return responsiveKey
        }
        return copy
    }
}
