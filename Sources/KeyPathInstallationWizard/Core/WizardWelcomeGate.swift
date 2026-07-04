import Foundation

/// Decides whether the wizard should open on the one-time Welcome page (issue #932).
///
/// The Welcome page is an overture shown before any diagnostics on a fresh install:
/// it explains what KeyPath is and previews the setup steps so macOS's permission
/// prompts feel expected. It shows until the user clicks "Get Started" once, then
/// never again (persisted via UserDefaults).
public enum WizardWelcomeGate {
    /// Set to true when the user clicks "Get Started" on the Welcome page.
    public static let hasSeenWelcomeKey = "wizard_has_seen_welcome"

    /// QA/debug override: forces the Welcome page on machines that are already set up.
    public static let forceWelcomeKey = "wizard_force_welcome"

    /// Pure decision: show Welcome on fresh installs (helper not yet installed)
    /// until the user has clicked Get Started. `forced` is a QA override.
    public static func shouldShowWelcome(
        helperInstalled: Bool,
        hasSeenWelcome: Bool,
        forced: Bool
    ) -> Bool {
        if forced { return true }
        return !helperInstalled && !hasSeenWelcome
    }

    /// Convenience wrapper reading the persisted flags from UserDefaults.
    public static func shouldShowWelcome(helperInstalled: Bool) -> Bool {
        let defaults = UserDefaults.standard
        return shouldShowWelcome(
            helperInstalled: helperInstalled,
            hasSeenWelcome: defaults.bool(forKey: hasSeenWelcomeKey),
            forced: defaults.bool(forKey: forceWelcomeKey)
        )
    }

    /// Persist that the user has completed the Welcome page.
    public static func markWelcomeSeen() {
        UserDefaults.standard.set(true, forKey: hasSeenWelcomeKey)
    }
}
