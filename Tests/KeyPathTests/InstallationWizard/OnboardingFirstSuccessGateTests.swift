import Foundation
@testable import KeyPathInstallationWizard
@preconcurrency import XCTest

/// Unit tests for the post-setup "first success" celebration gate (#954): the
/// one-shot show/hide decision that fills the "setup just completed for the first
/// time" gap left after the wizard closes.
final class OnboardingFirstSuccessGateTests: XCTestCase {
    // MARK: - Gate truth table

    func testFirstEverSuccessfulCloseShowsCelebration() {
        XCTAssertTrue(
            OnboardingFirstSuccessGate.shouldShowFirstSuccess(
                isEligibleForFirstSuccess: true, hasShownFirstSuccess: false, wizardClosedHealthy: true
            )
        )
    }

    func testAlreadyShownNeverShowsAgain() {
        XCTAssertFalse(
            OnboardingFirstSuccessGate.shouldShowFirstSuccess(
                isEligibleForFirstSuccess: true, hasShownFirstSuccess: true, wizardClosedHealthy: true
            )
        )
    }

    func testExistingWelcomeFlagWithoutNewEligibilitySkipsCelebration() {
        // Existing users may already have wizard_has_seen_welcome from #932. The
        // new rollout must not treat that old flag as a fresh setup completion.
        XCTAssertFalse(
            OnboardingFirstSuccessGate.shouldShowFirstSuccess(
                isEligibleForFirstSuccess: false, hasShownFirstSuccess: false, wizardClosedHealthy: true
            )
        )
    }

    func testUnhealthyCloseSkipsCelebration() {
        // Wizard closed but validation still shows blocking issues — not a success,
        // don't celebrate a setup that isn't actually done.
        XCTAssertFalse(
            OnboardingFirstSuccessGate.shouldShowFirstSuccess(
                isEligibleForFirstSuccess: true, hasShownFirstSuccess: false, wizardClosedHealthy: false
            )
        )
    }

    func testAllConditionsFalseSkipsCelebration() {
        XCTAssertFalse(
            OnboardingFirstSuccessGate.shouldShowFirstSuccess(
                isEligibleForFirstSuccess: false, hasShownFirstSuccess: true, wizardClosedHealthy: false
            )
        )
    }

    // MARK: - Persisted key stability

    /// The UserDefaults key names are load-bearing: a typo'd rename here would
    /// silently reset every existing install's one-shot state. Pin them explicitly.
    func testPersistedKeyNamesAreStable() {
        XCTAssertEqual(OnboardingFirstSuccessGate.hasShownFirstSuccessKey, "onboarding_first_success_shown")
        XCTAssertEqual(OnboardingFirstSuccessGate.isEligibleForFirstSuccessKey, "onboarding_first_success_eligible")
        XCTAssertEqual(WizardWelcomeGate.hasSeenWelcomeKey, "wizard_has_seen_welcome")
    }
}
