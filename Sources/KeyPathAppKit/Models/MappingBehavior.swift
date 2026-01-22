import Foundation

// MARK: - Mapping Behavior

/// Describes advanced key behavior beyond a simple remap.
/// When present on a KeyMapping, the generator emits tap-hold, tap-dance, or chord syntax.
public enum MappingBehavior: Codable, Equatable, Sendable {
    /// Dual-role key: tap produces one action, hold produces another.
    case dualRole(DualRoleBehavior)

    /// Tap-dance: different actions for single tap, double tap, etc.
    case tapDance(TapDanceBehavior)

    /// Chord: multiple keys pressed together produce a single output.
    case chord(ChordBehavior)
}

// MARK: - Dual Role

/// Settings for a tap-hold (dual-role) key.
///
/// **Variant Priority** (renderer uses first matching condition):
/// 1. `activateHoldOnOtherKey` → `tap-hold-press`
/// 2. `quickTap` → `tap-hold-release`
/// 3. `customTapKeys` (non-empty) → `tap-hold-release-keys`
/// 4. Otherwise → `tap-hold` (basic)
public struct DualRoleBehavior: Codable, Equatable, Sendable {
    /// Action when tapped (e.g., "a", "esc", or a macro string).
    public var tapAction: String

    /// Action when held (e.g., "lctl", "lmet", or layer switch).
    public var holdAction: String

    /// Milliseconds before a press is considered a hold. Default 200. Must be > 0.
    public var tapTimeout: Int

    /// Milliseconds for the hold to fully activate. Default 200. Must be > 0.
    public var holdTimeout: Int

    /// If true, any other key press while waiting triggers the hold action early.
    /// Maps to Kanata's `tap-hold-press` variant.
    public var activateHoldOnOtherKey: Bool

    /// If true, releasing before timeout still triggers tap even if another key was pressed.
    /// Maps to Kanata's `tap-hold-release` variant (quick-tap / permissive-hold behavior).
    public var quickTap: Bool

    /// List of keys that trigger early tap when pressed.
    /// Maps to Kanata's `tap-hold-release-keys` variant.
    /// Only used when `customTapKeys` is non-empty and other flags are false.
    public var customTapKeys: [String]

    public init(
        tapAction: String,
        holdAction: String,
        tapTimeout: Int = 200,
        holdTimeout: Int = 200,
        activateHoldOnOtherKey: Bool = false,
        quickTap: Bool = false,
        customTapKeys: [String] = []
    ) {
        self.tapAction = tapAction
        self.holdAction = holdAction
        // Clamp to minimum of 1ms to prevent invalid configs
        self.tapTimeout = max(1, tapTimeout)
        self.holdTimeout = max(1, holdTimeout)
        self.activateHoldOnOtherKey = activateHoldOnOtherKey
        self.quickTap = quickTap
        self.customTapKeys = customTapKeys
    }

    /// Returns true if the configuration is valid for rendering.
    public var isValid: Bool {
        !tapAction.isEmpty && !holdAction.isEmpty && tapTimeout > 0 && holdTimeout > 0
    }
}

// MARK: - Tap Dance

/// Settings for a tap-dance key.
public struct TapDanceBehavior: Codable, Equatable, Sendable {
    /// Time window (ms) to register additional taps. Default 200. Must be > 0.
    public var windowMs: Int

    /// Ordered list of actions for each tap count (index 0 = single tap, 1 = double, etc.).
    /// Must have at least one step with a non-empty action.
    public var steps: [TapDanceStep]

    public init(windowMs: Int = 200, steps: [TapDanceStep]) {
        // Clamp to minimum of 1ms to prevent invalid configs
        self.windowMs = max(1, windowMs)
        self.steps = steps
    }

    /// Returns true if the configuration is valid for rendering.
    public var isValid: Bool {
        windowMs > 0 && steps.contains { !$0.action.isEmpty }
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
    /// Uses `tap-hold-press` variant (hold activates immediately on other key press).
    static func homeRowMod(letter: String, modifier: String) -> DualRoleBehavior {
        DualRoleBehavior(
            tapAction: letter,
            holdAction: modifier,
            tapTimeout: 200,
            holdTimeout: 200,
            activateHoldOnOtherKey: true, // Best for home-row mods
            quickTap: false
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

// MARK: - Chord Behavior

/// Settings for a chord (multiple keys pressed together).
///
/// Chords allow combinations like j+k → Esc or s+d → Backspace.
/// Uses Kanata's `defchords` syntax for implementation.
public struct ChordBehavior: Codable, Equatable, Sendable {
    /// All keys in the chord (e.g., ["j", "k"]).
    /// Order doesn't matter - any order triggers the chord.
    public var keys: [String]

    /// Action when chord is triggered (e.g., "esc", "bspc", "C-x").
    public var output: String

    /// Time window (ms) for chord detection. Default 200. Must be > 0.
    /// Larger values make chords easier to trigger but may cause misfires.
    public var timeout: Int

    /// Optional human-readable description of the chord's purpose.
    public var description: String?

    public init(
        keys: [String],
        output: String,
        timeout: Int = 200,
        description: String? = nil
    ) {
        // Validation: need at least 2 keys for a chord
        precondition(keys.count >= 2, "ChordBehavior requires at least 2 keys")
        precondition(!output.isEmpty, "ChordBehavior output cannot be empty")

        self.keys = keys
        self.output = output
        // Clamp to minimum of 50ms to prevent unrealistic values
        self.timeout = max(50, timeout)
        self.description = description
    }

    /// Returns true if the configuration is valid for rendering.
    public var isValid: Bool {
        keys.count >= 2 && !output.isEmpty && timeout >= 50
    }

    /// A unique group name for this chord (used in Kanata defchords).
    /// Generated from the sorted keys to ensure consistency.
    public var groupName: String {
        "kp-chord-" + keys.sorted().joined(separator: "-")
    }
}

// MARK: - Chord Convenience Factories

public extension ChordBehavior {
    /// Create a simple two-key chord.
    static func twoKey(_ key1: String, _ key2: String, output: String, description: String? = nil) -> ChordBehavior {
        ChordBehavior(keys: [key1, key2], output: output, description: description)
    }

    /// Create a three-key chord.
    static func threeKey(_ key1: String, _ key2: String, _ key3: String, output: String, description: String? = nil) -> ChordBehavior {
        ChordBehavior(keys: [key1, key2, key3], output: output, description: description)
    }
}
