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
                hasSeenWelcome: true, hasShownFirstSuccess: false, wizardClosedHealthy: true
            )
        )
    }

    func testAlreadyShownNeverShowsAgain() {
        XCTAssertFalse(
            OnboardingFirstSuccessGate.shouldShowFirstSuccess(
                hasSeenWelcome: true, hasShownFirstSuccess: true, wizardClosedHealthy: true
            )
        )
    }

    func testNeverSawWelcomePageSkipsCelebration() {
        // A user who never went through the Welcome page (e.g. upgraded from an
        // older install, or the helper was already present) didn't take the
        // fresh-install onboarding arc, so the "first success" moment doesn't apply.
        XCTAssertFalse(
            OnboardingFirstSuccessGate.shouldShowFirstSuccess(
                hasSeenWelcome: false, hasShownFirstSuccess: false, wizardClosedHealthy: true
            )
        )
    }

    func testUnhealthyCloseSkipsCelebration() {
        // Wizard closed but validation still shows blocking issues — not a success,
        // don't celebrate a setup that isn't actually done.
        XCTAssertFalse(
            OnboardingFirstSuccessGate.shouldShowFirstSuccess(
                hasSeenWelcome: true, hasShownFirstSuccess: false, wizardClosedHealthy: false
            )
        )
    }

    func testAllConditionsFalseSkipsCelebration() {
        XCTAssertFalse(
            OnboardingFirstSuccessGate.shouldShowFirstSuccess(
                hasSeenWelcome: false, hasShownFirstSuccess: true, wizardClosedHealthy: false
            )
        )
    }

    // MARK: - Persisted key stability

    /// The UserDefaults key names are load-bearing: a typo'd rename here would
    /// silently reset every existing install's one-shot state. Pin them explicitly.
    func testPersistedKeyNamesAreStable() {
        XCTAssertEqual(OnboardingFirstSuccessGate.hasShownFirstSuccessKey, "onboarding_first_success_shown")
        XCTAssertEqual(WizardWelcomeGate.hasSeenWelcomeKey, "wizard_has_seen_welcome")
    }
}
