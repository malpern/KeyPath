import Foundation

// MARK: - Mapping Behavior

/// Describes advanced key behavior beyond a simple remap.
/// When present on a KeyMapping, the generator emits tap-hold or tap-dance syntax.
public enum MappingBehavior: Codable, Equatable, Sendable {
    /// Dual-role key: tap produces one action, hold produces another.
    case dualRole(DualRoleBehavior)

    /// Tap-dance: different actions for single tap, double tap, etc.
    case tapDance(TapDanceBehavior)
}

// MARK: - Dual Role

/// Settings for a tap-hold (dual-role) key.
public struct DualRoleBehavior: Codable, Equatable, Sendable {
    /// Action when tapped (e.g., "a", "esc", or a macro string).
    public var tapAction: String

    /// Action when held (e.g., "lctl", "lmet", or layer switch).
    public var holdAction: String

    /// Milliseconds before a press is considered a hold. Default 200.
    public var tapTimeout: Int

    /// Milliseconds for the hold to fully activate. Default 200.
    public var holdTimeout: Int

    /// Per-state timeout overrides (optional). Keys are state names like "tap", "hold".
    public var stateOverrides: [String: Int]?

    /// If true, any other key press while waiting triggers the hold action early.
    /// Maps to Kanata's `tap-hold-press` variant.
    public var activateHoldOnOtherKey: Bool

    /// If true, releasing before timeout still triggers tap even if another key was pressed.
    /// Maps to Kanata's quick-tap / permissive-hold behavior.
    public var quickTap: Bool

    public init(
        tapAction: String,
        holdAction: String,
        tapTimeout: Int = 200,
        holdTimeout: Int = 200,
        stateOverrides: [String: Int]? = nil,
        activateHoldOnOtherKey: Bool = false,
        quickTap: Bool = false
    ) {
        self.tapAction = tapAction
        self.holdAction = holdAction
        self.tapTimeout = tapTimeout
        self.holdTimeout = holdTimeout
        self.stateOverrides = stateOverrides
        self.activateHoldOnOtherKey = activateHoldOnOtherKey
        self.quickTap = quickTap
    }
}

// MARK: - Tap Dance

/// Settings for a tap-dance key.
public struct TapDanceBehavior: Codable, Equatable, Sendable {
    /// Time window (ms) to register additional taps. Default 200.
    public var windowMs: Int

    /// Ordered list of actions for each tap count (index 0 = single tap, 1 = double, etc.).
    public var steps: [TapDanceStep]

    public init(windowMs: Int = 200, steps: [TapDanceStep]) {
        self.windowMs = windowMs
        self.steps = steps
    }
}

/// A single step in a tap-dance sequence.
public struct TapDanceStep: Codable, Equatable, Sendable {
    /// Human-readable label (e.g., "Single tap", "Double tap").
    public var label: String

    /// The action to perform (key name, macro, etc.).
    public var action: String

    public init(label: String, action: String) {
        self.label = label
        self.action = action
    }
}

// MARK: - Convenience Factories

public extension DualRoleBehavior {
    /// Create a home-row mod behavior (letter on tap, modifier on hold).
    static func homeRowMod(letter: String, modifier: String) -> DualRoleBehavior {
        DualRoleBehavior(
            tapAction: letter,
            holdAction: modifier,
            tapTimeout: 200,
            holdTimeout: 200,
            activateHoldOnOtherKey: true,
            quickTap: true
        )
    }
}

public extension TapDanceBehavior {
    /// Create a simple two-step tap-dance (single tap, double tap).
    static func twoStep(singleTap: String, doubleTap: String, windowMs: Int = 200) -> TapDanceBehavior {
        TapDanceBehavior(
            windowMs: windowMs,
            steps: [
                TapDanceStep(label: "Single tap", action: singleTap),
                TapDanceStep(label: "Double tap", action: doubleTap)
            ]
        )
    }
}

