import Foundation
import KeyPathWizardCore

/// Owns the one-shot eligibility for the post-setup learning path.
///
/// The wizard's welcome page explains why KeyPath needs permissions. This gate
/// waits until that first run is healthy before offering a small, optional
/// sequence that teaches the app through useful keyboard changes.
public enum FirstSuccessOnboardingGate {
    public static let hasShownKey = "onboarding_first_success_shown"

    /// Decides whether the panel may be shown without consuming the one-shot
    /// opportunity. The presenter records success with `markPresented` only
    /// after the panel is actually visible.
    @MainActor
    public static func isEligible(
        didShowWelcomePage: Bool,
        wizardState: WizardSystemState,
        issues: [WizardIssue],
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard wizardState == .active,
              issues.isEmpty,
              didShowWelcomePage,
              !defaults.bool(forKey: hasShownKey)
        else {
            return false
        }

        return true
    }

    /// Records that the first-success panel was successfully presented.
    @MainActor
    public static func markPresented(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: hasShownKey)
    }
}
