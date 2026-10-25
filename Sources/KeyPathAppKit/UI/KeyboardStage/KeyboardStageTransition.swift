import Foundation

protocol KeyboardStageClock: Sendable {
    func now() -> TimeInterval
}

struct SystemKeyboardStageClock: KeyboardStageClock {
    func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

struct FixedKeyboardStageClock: KeyboardStageClock {
    var time: TimeInterval

    func now() -> TimeInterval {
        time
    }
}

struct KeyboardStageTransition: Equatable, Sendable {
    var start: KeyboardStageScene
    var target: KeyboardStageScene
    var startedAt: TimeInterval
    var duration: TimeInterval

    var endsAt: TimeInterval {
        startedAt + duration
    }

    func scene(at time: TimeInterval) -> KeyboardStageScene {
        KeyboardStageScene.interpolated(
            from: start,
            to: target,
            progress: progress(at: time)
        )
    }

    func progress(at time: TimeInterval) -> Float {
        guard duration > 0 else { return 1 }
        let linearProgress = Float((time - startedAt) / duration)
        return Self.criticallyDampedProgress(linearProgress)
    }

    /// Underdamped release: overshoots ~2.5% around 60% of the duration —
    /// the dome rebound of a physical keycap — then settles cleanly.
    static func underdampedReleaseProgress(_ rawProgress: Float) -> Float {
        let progress = min(1, max(0, rawProgress))
        guard progress > 0, progress < 1 else { return progress }
        return 1 - exp(-6 * progress) * cos(4.712 * progress)
    }

    static func criticallyDampedProgress(_ rawProgress: Float) -> Float {
        let progress = min(1, max(0, rawProgress))
        guard progress > 0, progress < 1 else { return progress }

        let response: Float = 8
        let value = 1 - (1 + response * progress) * exp(-response * progress)
        let settledValue = 1 - (1 + response) * exp(-response)
        return min(1, max(0, value / settledValue))
    }
}

struct KeyboardStagePresentation: Equatable, Sendable {
    private(set) var settledScene: KeyboardStageScene
    private(set) var transition: KeyboardStageTransition?
    private(set) var revision: Int

    init(scene: KeyboardStageScene) {
        settledScene = scene
        transition = nil
        revision = 0
    }

    var isAnimating: Bool {
        transition != nil
    }

    func scene(at time: TimeInterval) -> KeyboardStageScene {
        transition?.scene(at: time) ?? settledScene
    }

    func remainingDuration(at time: TimeInterval) -> TimeInterval {
        guard let transition else { return 0 }
        return max(0, transition.endsAt - time)
    }

    mutating func retarget(
        to target: KeyboardStageScene,
        at time: TimeInterval,
        reduceMotion: Bool
    ) {
        let current = scene(at: time)
        guard current != target else {
            settle(on: target)
            return
        }

        revision &+= 1
        if reduceMotion || target.transitionDuration <= 0 {
            settledScene = target
            transition = nil
            return
        }

        settledScene = current
        transition = KeyboardStageTransition(
            start: current,
            target: target,
            startedAt: time,
            duration: target.transitionDuration
        )
    }

    mutating func settle() {
        guard let transition else { return }
        settle(on: transition.target)
    }

    mutating func settle(on scene: KeyboardStageScene) {
        settledScene = scene
        transition = nil
        revision &+= 1
    }
}
