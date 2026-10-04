import Foundation
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

final class FirstSuccessOnboardingGateTests: XCTestCase {
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
    func testSessionPostStartRefreshSuppressesUnsupportedTourAfterHealthyVerification() async {
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
        XCTAssertEqual(presentationCount, 0)
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
    func testSessionTourIsUnavailableWithoutConsumingFirstRunOpportunity() {
        XCTAssertFalse(FirstSuccessOnboardingGate.supportsTour())
        XCTAssertFalse(FirstSuccessOnboardingGate.supportsTour(backend: .session))
        XCTAssertTrue(FirstSuccessOnboardingGate.supportsTour(backend: .driverKit))
        withIsolatedDefaults { defaults in
            XCTAssertFalse(FirstSuccessOnboardingGate.isEligible(
                didShowWelcomePage: true, wizardState: .active, issues: [],
                backend: .session, defaults: defaults
            ))
            XCTAssertFalse(defaults.bool(forKey: FirstSuccessOnboardingGate.hasShownKey))
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
