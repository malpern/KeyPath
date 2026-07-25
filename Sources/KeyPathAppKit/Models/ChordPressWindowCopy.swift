import Foundation
import KeyPathRulesCore

/// Canonical user-facing explanations for a chord group's timing control.
enum ChordPressWindowCopy {
    static let title = LocalizedStringResource(
        "Chord press window",
        comment: "Name of the timing control that determines how quickly all keys in a chord must be pressed."
    )

    static let explanation = LocalizedStringResource(
        "The window starts when you press the first chord key. Press the last required key before it expires; otherwise, the keys use their normal layer actions.",
        comment: "Explains when chord timing starts, what completes a chord, and what happens when time expires."
    )

    static let tradeoff = LocalizedStringResource(
        "Lower values make normal actions respond sooner but require a more precise chord. Higher values make chords easier but delay normal-action fallback.",
        comment: "Explains the physical effect of changing the chord press window."
    )

    static func summary(milliseconds: Int) -> String {
        String(
            localized: "Chord press window: \(milliseconds) ms",
            comment: "Compact chord group summary. The variable is the timing window in milliseconds."
        )
    }

    static func compactSummary(milliseconds: Int) -> String {
        String(
            localized: "\(milliseconds) ms window",
            comment: "Short chord press window value for repeated sidebar rows. The variable is milliseconds."
        )
    }

    static func accessibilityValue(milliseconds: Int, speed: ChordSpeed) -> String {
        String(
            localized: "\(milliseconds) milliseconds, \(speed.rawValue). Lower values give faster fallback; higher values give an easier chord.",
            comment: "Accessibility value for the chord press window. The first variable is milliseconds; the second is the preset name."
        )
    }
}
