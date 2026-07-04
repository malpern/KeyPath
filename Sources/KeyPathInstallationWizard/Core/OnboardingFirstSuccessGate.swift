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

    /// Set when this version's Welcome page starts a fresh setup flow. This is
    /// intentionally separate from `wizard_has_seen_welcome`, which already
    /// exists on older installs and would otherwise make the rollout celebrate
    /// routine repair/recheck wizard closes for established users.
    public static let isEligibleForFirstSuccessKey = "onboarding_first_success_eligible"

    /// Pure decision: show the celebration only for a user who has been through
    /// this version's Welcome-started onboarding flow, has never seen the
    /// celebration before, and whose wizard run just closed with the system
    /// validating healthy.
    public static func shouldShowFirstSuccess(
        isEligibleForFirstSuccess: Bool,
        hasShownFirstSuccess: Bool,
        wizardClosedHealthy: Bool
    ) -> Bool {
        isEligibleForFirstSuccess && !hasShownFirstSuccess && wizardClosedHealthy
    }

    /// Convenience wrapper reading the persisted flags from UserDefaults.
    public static func shouldShowFirstSuccess(wizardClosedHealthy: Bool) -> Bool {
        let defaults = UserDefaults.standard
        return shouldShowFirstSuccess(
            isEligibleForFirstSuccess: defaults.bool(forKey: isEligibleForFirstSuccessKey),
            hasShownFirstSuccess: defaults.bool(forKey: hasShownFirstSuccessKey),
            wizardClosedHealthy: wizardClosedHealthy
        )
    }

    /// Persist that this install started the fresh onboarding flow. Kept separate
    /// from Welcome's own one-shot so upgrades from #932 do not look fresh.
    public static func markFreshOnboardingEligible() {
        UserDefaults.standard.set(true, forKey: isEligibleForFirstSuccessKey)
    }

    /// Persist that the celebration has been shown (one-shot, regardless of how
    /// far the user got through it).
    public static func markFirstSuccessShown() {
        UserDefaults.standard.set(true, forKey: hasShownFirstSuccessKey)
    }
}
