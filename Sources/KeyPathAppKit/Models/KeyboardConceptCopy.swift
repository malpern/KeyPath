import KeyPathRulesCore

/// Canonical user-facing explanations for KeyPath's activation concepts.
///
/// Keep first-use UI copy based on these definitions so Leader and Hyper do not
/// acquire different meanings in the catalog, editors, and onboarding.
enum KeyboardConceptCopy {
    static let leaderDefinition =
        "Your Leader key is the starting key for KeyPath layers and sequences. It is Space by default."

    static let hyperDefinition =
        "Hyper combines Control, Option, Command, and Shift into one shortcut modifier. Caps Lock Remap provides it by default when you hold Caps Lock."

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
                "\(hyperDefinition) Hold your Hyper key, then press a shortcut key."
            case .tap:
                "\(hyperDefinition) Tap your Hyper key to turn the launcher on or off, then press a shortcut key."
            }
        case .leaderSequence:
            "\(leaderDefinition) Press \(leaderKeyDisplay), then L, then a shortcut key."
        }
    }
}
