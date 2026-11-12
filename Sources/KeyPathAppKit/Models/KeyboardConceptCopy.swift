import KeyPathRulesCore

/// Canonical user-facing explanations for KeyPath's activation concepts.
///
/// Keep first-use UI copy based on these definitions so Leader and Hyper do not
/// acquire different meanings in the catalog, editors, and onboarding.
enum KeyboardConceptCopy {
    /// Formats the primary instruction shown on a rule card.
    ///
    /// Keep activation separate from counts, delays, and prerequisites: those
    /// describe a rule, but do not tell someone what to physically do.
    static func activationHint(_ instruction: String) -> String {
        String(localized: "Use: \(instruction)")
    }

    static let leaderMeaning =
        String(localized: "Your Leader key is the starting key for KeyPath layers and sequences.")

    static let leaderDefinition =
        String(localized: "\(leaderMeaning) It is Space by default.")

    static let hyperDefinition =
        String(
            localized: "Hyper combines Control, Option, Command, and Shift into one modifier. Apps rarely use all four together, so Hyper creates clean shortcuts that are unlikely to conflict. Caps Lock Remap provides Hyper by default when you hold Caps Lock."
        )

    static let hyperInlineDefinition =
        String(localized: "Hyper combines all four modifiers, creating clean shortcuts apps rarely use.")

    static let leaderCatalogSummary =
        String(localized: "\(leaderDefinition) Choose Space, Caps Lock, Tab, or Backtick.")

    static let launcherCatalogSummary =
        String(localized: "\(hyperDefinition) Use it with a shortcut key to launch an app or website.")

    static let leaderPackDescription =
        String(localized: "\(leaderDefinition) Choose Space, Caps Lock, Tab, or Backtick once, and every layer follows your choice.")

    static let launcherPackDescription =
        String(localized: "\(hyperDefinition) Hold your Hyper key and press a shortcut key, or switch Quick Launcher to Leader → L activation.")

    static func launcherActivationDescription(
        mode: LauncherActivationMode,
        hyperTriggerMode: HyperTriggerMode,
        leaderKeyDisplay: String = String(localized: "your Leader key", comment: "Fills a sentence such as 'Press your Leader key, then L'")
    ) -> String {
        switch mode {
        case .holdHyper:
            switch hyperTriggerMode {
            case .hold:
                String(localized: "\(hyperInlineDefinition) Hold your Hyper key, then press a shortcut key.")
            case .tap:
                String(localized: "\(hyperInlineDefinition) Tap your Hyper key to turn the launcher on or off, then press a shortcut key.")
            }
        case .leaderSequence:
            String(localized: "\(leaderMeaning) Press \(leaderKeyDisplay), then L, then a shortcut key.")
        }
    }
}
