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
        "Use: \(instruction)"
    }

    static let leaderMeaning =
        "Your Leader key is the starting key for KeyPath layers and sequences."

    static let leaderDefinition =
        "\(leaderMeaning) It is Space by default."

    static let hyperDefinition =
        "Hyper combines Control, Option, Command, and Shift into one modifier. Apps rarely use all four together, so Hyper creates clean shortcuts that are unlikely to conflict. Caps Lock Remap provides Hyper by default when you hold Caps Lock."

    static let hyperInlineDefinition =
        "Hyper combines all four modifiers, creating clean shortcuts apps rarely use."

    static let leaderCatalogSummary =
        "\(leaderDefinition) Choose Space, Caps Lock, Tab, or Backtick."

    static let launcherCatalogSummary =
        "\(hyperDefinition) Use it with a shortcut key to launch an app or website."

    static let leaderPackDescription =
        "\(leaderDefinition) Choose Space, Caps Lock, Tab, or Backtick once, and every layer follows your choice."

    static let launcherPackDescription =
        "\(hyperDefinition) Hold your Hyper key and press a shortcut key, or switch Quick Launcher to Leader → L activation."

    static func launcherActivationDescription(
        mode: LauncherActivationMode,
        hyperTriggerMode: HyperTriggerMode,
        leaderKeyDisplay: String = "your Leader key"
    ) -> String {
        switch mode {
        case .holdHyper:
            switch hyperTriggerMode {
            case .hold:
                "\(hyperInlineDefinition) Hold your Hyper key, then press a shortcut key."
            case .tap:
                "\(hyperInlineDefinition) Tap your Hyper key to turn the launcher on or off, then press a shortcut key."
            }
        case .leaderSequence:
            "\(leaderMeaning) Press \(leaderKeyDisplay), then L, then a shortcut key."
        }
    }
}
