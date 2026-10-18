import Foundation
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

final class FirstSuccessOnboardingGateTests: XCTestCase {
    @MainActor
    func testInterruptedSetupRemainsPendingAcrossDefaultsReloadUntilTourPresentation() {
        let suite = "KeyPath.tour-resume.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(FirstSuccessOnboardingGate.isPending(defaults: defaults))
        defaults.set(true, forKey: WizardWelcomeGate.hasSeenWelcomeKey)
        let resumed = UserDefaults(suiteName: suite)!
        XCTAssertTrue(FirstSuccessOnboardingGate.isPending(defaults: resumed))
        XCTAssertTrue(FirstSuccessOnboardingGate.isEligible(
            didShowWelcomePage: false, wizardState: .active, issues: [], defaults: resumed
        ))
        FirstSuccessOnboardingGate.markPresented(defaults: resumed)
        XCTAssertFalse(FirstSuccessOnboardingGate.isPending(defaults: defaults))
    }

    @MainActor
    func testHealthyWelcomeLedSetupIsEligibleWithoutConsumingTheLearningPath() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(
                FirstSuccessOnboardingGate.isEligible(
                    didShowWelcomePage: true,
                    wizardState: .active,
                    issues: [],
                    backend: .driverKit,
                    defaults: defaults
                )
            )
            XCTAssertFalse(defaults.bool(forKey: FirstSuccessOnboardingGate.hasShownKey))
        }
    }

    @MainActor
    func testExistingUserRevisitingSetupIsNotTreatedAsFirstRun() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(
                FirstSuccessOnboardingGate.isEligible(
                    didShowWelcomePage: false,
                    wizardState: .active,
                    issues: [],
                    backend: .driverKit,
                    defaults: defaults
                )
            )
        }
    }

    @MainActor
    func testLearningPathRemainsEligibleUntilPresentationIsMarked() {
        withIsolatedDefaults { defaults in
            XCTAssertTrue(
                FirstSuccessOnboardingGate.isEligible(
                    didShowWelcomePage: true,
                    wizardState: .active,
                    issues: [],
                    backend: .driverKit,
                    defaults: defaults
                )
            )
            XCTAssertTrue(
                FirstSuccessOnboardingGate.isEligible(
                    didShowWelcomePage: true,
                    wizardState: .active,
                    issues: [],
                    backend: .driverKit,
                    defaults: defaults
                )
            )

            FirstSuccessOnboardingGate.markPresented(defaults: defaults)

            XCTAssertTrue(defaults.bool(forKey: FirstSuccessOnboardingGate.hasShownKey))
            XCTAssertFalse(
                FirstSuccessOnboardingGate.isEligible(
                    didShowWelcomePage: true,
                    wizardState: .active,
                    issues: [],
                    backend: .driverKit,
                    defaults: defaults
                )
            )
        }
    }

    @MainActor
    func testSessionPostStartRefreshPresentsTourAfterHealthyVerification() async {
        let defaults = UserDefaults.standard
        let previousShownValue = defaults.object(
            forKey: FirstSuccessOnboardingGate.hasShownKey
        )
        defaults.set(false, forKey: FirstSuccessOnboardingGate.hasShownKey)
        defer {
            if let previousShownValue {
                defaults.set(previousShownValue, forKey: FirstSuccessOnboardingGate.hasShownKey)
            } else {
                defaults.removeObject(forKey: FirstSuccessOnboardingGate.hasShownKey)
            }
        }

        var presentationCount = 0
        let view = InstallationWizardView(
            onFirstSuccess: { presentationCount += 1 },
            didShowWelcomePage: true,
            postStartStateDetector: {
                SystemStateResult(
                    state: .active,
                    issues: [],
                    autoFixActions: [],
                    detectionTimestamp: Date()
                )
            },
            // Drive dismissal without touching @Environment: this view is never
            // installed in a hierarchy, and reading the environment's dismiss
            // action on an uninstalled view emits a SwiftUI runtime warning.
            dismissHandler: {}
        )
        view.stateMachine.updateWizardState(.serviceNotRunning, issues: [])

        await view.refreshPostStartStateAndDismiss()

        XCTAssertEqual(view.stateMachine.wizardState, .active)
        XCTAssertEqual(presentationCount, 1)
    }

    @MainActor
    func testPostStartRefreshDoesNotRequestOnboardingWhenVerificationIsUnhealthy() async {
        let defaults = UserDefaults.standard
        let previousShownValue = defaults.object(
            forKey: FirstSuccessOnboardingGate.hasShownKey
        )
        defaults.set(false, forKey: FirstSuccessOnboardingGate.hasShownKey)
        defer {
            if let previousShownValue {
                defaults.set(previousShownValue, forKey: FirstSuccessOnboardingGate.hasShownKey)
            } else {
                defaults.removeObject(forKey: FirstSuccessOnboardingGate.hasShownKey)
            }
        }

        var presentationCount = 0
        let view = InstallationWizardView(
            onFirstSuccess: { presentationCount += 1 },
            didShowWelcomePage: true,
            postStartStateDetector: {
                SystemStateResult(
                    state: .serviceNotRunning,
                    issues: [],
                    autoFixActions: [],
                    detectionTimestamp: Date()
                )
            },
            // Drive dismissal without touching @Environment: this view is never
            // installed in a hierarchy, and reading the environment's dismiss
            // action on an uninstalled view emits a SwiftUI runtime warning.
            dismissHandler: {}
        )
        await view.refreshPostStartStateAndDismiss()

        XCTAssertEqual(view.stateMachine.wizardState, .serviceNotRunning)
        XCTAssertEqual(presentationCount, 0)
    }

    @MainActor
    func testSessionTourIsAvailableWithoutConsumingFirstRunOpportunity() {
        XCTAssertTrue(FirstSuccessOnboardingGate.supportsTour())
        XCTAssertTrue(FirstSuccessOnboardingGate.supportsTour(backend: .session))
        XCTAssertTrue(FirstSuccessOnboardingGate.supportsTour(backend: .driverKit))
        withIsolatedDefaults { defaults in
            XCTAssertTrue(FirstSuccessOnboardingGate.isEligible(
                didShowWelcomePage: true, wizardState: .active, issues: [],
                backend: .session, defaults: defaults
            ))
            XCTAssertFalse(defaults.bool(forKey: FirstSuccessOnboardingGate.hasShownKey))
        }
    }

    @MainActor
    func testResumedWelcomeLedSetupStillOffersUnseenTour() {
        withIsolatedDefaults { defaults in
            defaults.set(true, forKey: WizardWelcomeGate.hasSeenWelcomeKey)
            XCTAssertTrue(FirstSuccessOnboardingGate.isEligible(
                didShowWelcomePage: false, wizardState: .active, issues: [],
                backend: .session, defaults: defaults
            ))
            FirstSuccessOnboardingGate.markPresented(defaults: defaults)
            XCTAssertFalse(FirstSuccessOnboardingGate.isEligible(
                didShowWelcomePage: false, wizardState: .active, issues: [],
                backend: .session, defaults: defaults
            ))
        }
    }

    @MainActor
    private func withIsolatedDefaults(_ assertions: (UserDefaults) -> Void) {
        let suiteName = "FirstSuccessOnboardingGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        assertions(defaults)
    }
}
