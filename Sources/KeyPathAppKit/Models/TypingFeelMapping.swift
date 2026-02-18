import Foundation

/// Pure mapping logic between the "Typing Feel" slider and raw `TimingConfig` values.
/// No UI — this is the bidirectional projection that lets a single slider control
/// tapWindow and holdDelay simultaneously.
public enum TypingFeelMapping {
    // MARK: - Feel Slider ↔ Raw Values

    /// Slider extremes (position 0.0 = "More Letters", 1.0 = "More Modifiers").
    /// Both ranges are 100ms so the default (200, 150) lands exactly at 0.5.
    private static let tapWindowRange = (min: 150, max: 250) // ms
    private static let holdDelayRange = (min: 100, max: 200) // ms

    /// Convert a slider position (0.0–1.0) to raw timing values.
    /// Position 0.0 ("More Letters"): tapWindow=250, holdDelay=200
    /// Position 0.5 (default): tapWindow=200, holdDelay=150
    /// Position 1.0 ("More Modifiers"): tapWindow=150, holdDelay=100
    public static func timingValues(forSliderPosition position: Double) -> (tapWindow: Int, holdDelay: Int) {
        let clamped = min(max(position, 0), 1)
        // Inverted: 0.0 maps to max (slow/forgiving), 1.0 maps to min (fast/aggressive)
        let tapWindow = Int(round(Double(tapWindowRange.max) - clamped * Double(tapWindowRange.max - tapWindowRange.min)))
        let holdDelay = Int(round(Double(holdDelayRange.max) - clamped * Double(holdDelayRange.max - holdDelayRange.min)))
        return (tapWindow, holdDelay)
    }

    /// Derive slider position from raw values. Returns `nil` if values don't lie on
    /// the linear curve (user edited in Expert mode → UI should show "Custom").
    public static func sliderPosition(tapWindow: Int, holdDelay: Int) -> Double? {
        let tapSpan = Double(tapWindowRange.max - tapWindowRange.min)
        let holdSpan = Double(holdDelayRange.max - holdDelayRange.min)

        guard tapSpan > 0, holdSpan > 0 else { return nil }

        let tapPosition = Double(tapWindowRange.max - tapWindow) / tapSpan
        let holdPosition = Double(holdDelayRange.max - holdDelay) / holdSpan

        // Both must be in range
        guard tapPosition >= -0.001, tapPosition <= 1.001,
              holdPosition >= -0.001, holdPosition <= 1.001
        else { return nil }

        // Both must agree (within rounding tolerance)
        guard abs(tapPosition - holdPosition) < 0.05 else { return nil }

        let average = (tapPosition + holdPosition) / 2
        return min(max(average, 0), 1)
    }

    /// Snap raw values to the nearest position on the slider curve.
    /// Used when switching from raw mode back to slider mode.
    public static func snapToCurve(tapWindow: Int, holdDelay: Int) -> (tapWindow: Int, holdDelay: Int) {
        if let position = sliderPosition(tapWindow: tapWindow, holdDelay: holdDelay) {
            return timingValues(forSliderPosition: position)
        }
        // Values are off-curve — find the closest slider position by averaging
        let tapSpan = Double(tapWindowRange.max - tapWindowRange.min)
        let holdSpan = Double(holdDelayRange.max - holdDelayRange.min)
        let tapPos = tapSpan > 0 ? Double(tapWindowRange.max - tapWindow) / tapSpan : 0.5
        let holdPos = holdSpan > 0 ? Double(holdDelayRange.max - holdDelay) / holdSpan : 0.5
        let avgPosition = min(max((tapPos + holdPos) / 2, 0), 1)
        // Round to nearest step (0.05) to match slider granularity
        let snapped = (avgPosition * 20).rounded() / 20
        return timingValues(forSliderPosition: snapped)
    }

    /// Dynamic helper text for the current slider position.
    public static func helperText(forSliderPosition position: Double) -> String {
        switch position {
        case 0 ..< 0.3:
            "Favors fast typing. Longer window before a hold registers."
        case 0.3 ..< 0.7:
            "Balanced. Works well for most users."
        case 0.7 ... 1.0:
            "Modifiers trigger quickly. Best for shortcut-heavy workflows."
        default:
            "Balanced. Works well for most users."
        }
    }

    // MARK: - Per-Finger Sensitivity

    /// Finger groups that pair left/right home-row keys.
    public enum FingerGroup: String, CaseIterable, Sendable {
        case pinky
        case ring
        case middle
        case index

        /// The two canonical keys for this finger group.
        public var keys: (left: String, right: String) {
            switch self {
            case .pinky: ("a", ";")
            case .ring: ("s", "l")
            case .middle: ("d", "k")
            case .index: ("f", "j")
            }
        }

        public var displayName: String {
            rawValue.capitalized
        }
    }

    /// Read the current sensitivity offset for a finger group.
    /// Returns `nil` if the finger's keys have inconsistent tap vs hold offsets
    /// (i.e., left tap != left hold, or left != right).
    public static func fingerSensitivity(for finger: FingerGroup, in timing: TimingConfig) -> Int? {
        let (left, right) = finger.keys
        let leftTap = timing.tapOffsets[left] ?? 0
        let leftHold = timing.holdOffsets[left] ?? 0
        let rightTap = timing.tapOffsets[right] ?? 0
        let rightHold = timing.holdOffsets[right] ?? 0

        // All four values must match for a clean reading
        guard leftTap == leftHold, leftTap == rightTap, leftTap == rightHold else {
            return nil
        }
        return leftTap
    }

    /// Apply a uniform sensitivity offset to both keys in a finger group.
    /// Sets the same value for tap and hold offsets. Range: 0–80ms.
    public static func applyFingerSensitivity(_ ms: Int, for finger: FingerGroup, to timing: inout TimingConfig) {
        let clamped = min(max(ms, 0), 80)
        let (left, right) = finger.keys

        if clamped == 0 {
            timing.tapOffsets.removeValue(forKey: left)
            timing.tapOffsets.removeValue(forKey: right)
            timing.holdOffsets.removeValue(forKey: left)
            timing.holdOffsets.removeValue(forKey: right)
        } else {
            timing.tapOffsets[left] = clamped
            timing.tapOffsets[right] = clamped
            timing.holdOffsets[left] = clamped
            timing.holdOffsets[right] = clamped
        }
    }
}
