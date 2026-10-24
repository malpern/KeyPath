import Foundation

/// Decides when the keyboard overlay appears on its own because a layer is active.
///
/// Pure state machine: the controller feeds it events and carries out the effects
/// (timers, showing, hiding), so the rules are testable without windows.
///
/// - Hold trigger: the overlay appears only after the layer has been held for
///   `revealDelay` without a key being pressed. Quick moves (hold Space, tap j)
///   never flash it; it shows up when you pause because you need it.
/// - Tap trigger: tapping the layer key on is a request to see it, so it appears at once.
/// - It leaves alone an overlay the user opened themselves.
/// - "Show only while a layer is held" turns the reveal on whatever the
///   "While a Layer Is Active" choice is: it is how that mode shows the overlay at all.
struct OverlayLayerRevealPolicy: Equatable {
    struct Configuration: Equatable {
        var isEnabled: Bool
        var revealDelay: TimeInterval
        var cancelOnKeyPress: Bool
        var concealDelay: TimeInterval = 0.15

        static let disabled = Configuration(isEnabled: false, revealDelay: 0, cancelOnKeyPress: false)

        static func make(
            displayMode: ContextHUDDisplayMode,
            triggerMode: ContextHUDTriggerMode,
            showsOnlyWhileLayerHeld: Bool = false
        ) -> Configuration {
            let showsOverlay = showsOnlyWhileLayerHeld || displayMode == .overlayOnly || displayMode == .both
            switch triggerMode {
            case .holdToShow:
                return Configuration(isEnabled: showsOverlay, revealDelay: 0.35, cancelOnKeyPress: true)
            case .tapToToggle:
                return Configuration(isEnabled: showsOverlay, revealDelay: 0, cancelOnKeyPress: false)
            }
        }
    }

    enum State: Equatable {
        case idle
        /// A layer is active; waiting to see whether the user pauses.
        case pending
        /// A key was pressed before the reveal, so stay hidden until the layer ends.
        case declined
        /// The overlay is showing because of the layer.
        case revealed
    }

    enum Effect: Equatable {
        case scheduleReveal(after: TimeInterval)
        case cancelReveal
        case show
        case scheduleConceal(after: TimeInterval)
        case cancelConceal
        case hide
    }

    private(set) var state: State = .idle
    var configuration: Configuration

    /// A layer change. `isBase` is true when no layer is active.
    /// `overlayAlreadyVisible` is true when the user opened the overlay themselves.
    mutating func layerChanged(isBase: Bool, overlayAlreadyVisible: Bool) -> [Effect] {
        if isBase {
            switch state {
            case .pending:
                state = .idle
                return [.cancelReveal]
            case .declined:
                state = .idle
                return []
            case .revealed:
                return [.scheduleConceal(after: configuration.concealDelay)]
            case .idle:
                return []
            }
        }

        switch state {
        case .revealed:
            // Moving between layers (or back before the conceal fired) keeps it up.
            return [.cancelConceal]
        case .pending, .declined:
            return []
        case .idle:
            guard configuration.isEnabled, !overlayAlreadyVisible else { return [] }
            if configuration.revealDelay <= 0 {
                state = .revealed
                return [.show]
            }
            state = .pending
            return [.scheduleReveal(after: configuration.revealDelay)]
        }
    }

    mutating func keyPressed() -> [Effect] {
        guard state == .pending, configuration.cancelOnKeyPress else { return [] }
        state = .declined
        return [.cancelReveal]
    }

    mutating func revealTimerFired() -> [Effect] {
        guard state == .pending else { return [] }
        state = .revealed
        return [.show]
    }

    mutating func concealTimerFired() -> [Effect] {
        guard state == .revealed else { return [] }
        state = .idle
        return [.hide]
    }

    /// The user showed or hid the overlay themselves; it is theirs again.
    mutating func userTookControl() -> [Effect] {
        let previous = state
        state = .idle
        switch previous {
        case .pending: return [.cancelReveal]
        case .revealed: return [.cancelConceal]
        case .idle, .declined: return []
        }
    }
}
