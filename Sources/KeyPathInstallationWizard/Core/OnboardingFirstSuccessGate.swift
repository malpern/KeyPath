import Foundation

/// Decides whether to show the post-setup "first success" celebration (issue #954).
///
/// Today the wizard simply closes back to the splash window on success: no
/// celebration, no next step. This gate fills that gap by recognizing "setup just
/// completed for the first time" — the moment the wizard closes healthy on a run
/// where the user was shown the one-time Welcome page (issue #932) — and gates the
/// celebration + starter-collection offer + short panel tour to show exactly once.
public enum OnboardingFirstSuccessGate {
    /// Set to true once the celebration panel has been shown. One-shot: never
    /// shows again after this, even across later wizard repairs/reopens.
    public static let hasShownFirstSuccessKey = "onboarding_first_success_shown"

    /// Pure decision: show the celebration only for a user who has been through
    /// the Welcome page, has never seen the celebration before, and whose wizard
    /// run just closed with the system validating healthy.
    public static func shouldShowFirstSuccess(
        hasSeenWelcome: Bool,
        hasShownFirstSuccess: Bool,
        wizardClosedHealthy: Bool
    ) -> Bool {
        hasSeenWelcome && !hasShownFirstSuccess && wizardClosedHealthy
    }

    /// Convenience wrapper reading the persisted flags from UserDefaults.
    /// Reuses `WizardWelcomeGate.hasSeenWelcomeKey` so the celebration is gated on
    /// the same "did this user go through onboarding" signal as the Welcome page.
    public static func shouldShowFirstSuccess(wizardClosedHealthy: Bool) -> Bool {
        let defaults = UserDefaults.standard
        return shouldShowFirstSuccess(
            hasSeenWelcome: defaults.bool(forKey: WizardWelcomeGate.hasSeenWelcomeKey),
            hasShownFirstSuccess: defaults.bool(forKey: hasShownFirstSuccessKey),
            wizardClosedHealthy: wizardClosedHealthy
        )
    }

    /// Persist that the celebration has been shown (one-shot, regardless of how
    /// far the user got through it).
    public static func markFirstSuccessShown() {
        UserDefaults.standard.set(true, forKey: hasShownFirstSuccessKey)
    }
}
