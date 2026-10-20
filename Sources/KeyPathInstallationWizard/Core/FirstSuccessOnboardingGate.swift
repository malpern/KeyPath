import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Owns the one-shot eligibility for the post-setup learning path.
///
/// The wizard's welcome page explains why KeyPath needs permissions. This gate
/// waits until that first run is healthy before offering a small, optional
/// sequence that teaches the app through useful keyboard changes.
public enum FirstSuccessOnboardingGate {
    public static let hasShownKey = "onboarding_first_success_shown"

    /// Both backends support the tour; session startup prepares the Caps Lock mapping.
    public static func supportsTour(backend _: KanataRuntimeBackend = .selected) -> Bool {
        true
    }

    /// Survives quitting during permission setup. Runtime readiness must not
    /// skip the wizard's verified handoff while this learning path is pending.
    public static func isPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: WizardWelcomeGate.hasSeenWelcomeKey)
            && !defaults.bool(forKey: hasShownKey)
    }

    /// Decides whether the panel may be shown without consuming the one-shot
    /// opportunity. The presenter records success with `markPresented` only
    /// after the panel is actually visible.
    @MainActor
    public static func isEligible(
        didShowWelcomePage: Bool,
        wizardState: WizardSystemState,
        issues: [WizardIssue],
        backend: KanataRuntimeBackend = .selected,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard supportsTour(backend: backend),
              wizardState == .active,
              issues.isEmpty,
              didShowWelcomePage || defaults.bool(forKey: WizardWelcomeGate.hasSeenWelcomeKey),
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
