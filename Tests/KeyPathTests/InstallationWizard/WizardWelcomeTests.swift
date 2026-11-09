import Foundation
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

/// Unit tests for the one-time Welcome page (#932): the show/hide gate,
/// and the guarantees that keep welcome out of the step sequence and routing.
final class WizardWelcomeTests: XCTestCase {
    // MARK: - Gate truth table

    func testFreshInstallUnseenShowsWelcome() {
        XCTAssertTrue(
            WizardWelcomeGate.shouldShowWelcome(
                hasSeenWelcome: false, forced: false
            )
        )
    }

    func testSeenWelcomeNeverShowsAgain() {
        XCTAssertFalse(
            WizardWelcomeGate.shouldShowWelcome(
                hasSeenWelcome: true, forced: false
            )
        )
    }

    func testForceOverrideAlwaysShowsWelcome() {
        XCTAssertTrue(
            WizardWelcomeGate.shouldShowWelcome(
                hasSeenWelcome: true, forced: true
            )
        )
    }

    @MainActor
    func testWizardHonorsPersistedWelcomeAcrossRelaunch() {
        let suite = "KeyPath.welcome-resume.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(InstallationWizardView().shouldShowWelcomePage(defaults: defaults))

        defaults.set(true, forKey: WizardWelcomeGate.hasSeenWelcomeKey)
        let relaunchedDefaults = UserDefaults(suiteName: suite)!
        XCTAssertFalse(InstallationWizardView().shouldShowWelcomePage(defaults: relaunchedDefaults))

        relaunchedDefaults.set(true, forKey: WizardWelcomeGate.forceWelcomeKey)
        XCTAssertTrue(InstallationWizardView().shouldShowWelcomePage(defaults: relaunchedDefaults))
    }

    // MARK: - Welcome stays out of the step sequence

    func testWelcomeIsNotAnOrderedPage() {
        XCTAssertFalse(
            WizardPage.orderedPages.contains(.welcome),
            "Welcome is a one-time overture, not a numbered wizard step; adding it to orderedPages would give it a step dot and back/forward slots"
        )
    }

    func testWelcomeHasNoStepPosition() {
        XCTAssertNil(WizardPage.welcome.stepPosition())
    }

    // MARK: - Routing never targets or lingers on welcome

    func testWelcomeHasNoRelevantIssues() {
        XCTAssertFalse(
            WizardRouter.pageHasRelevantIssues(.welcome, issues: [], state: .initializing)
        )
    }

    func testNextPageFromWelcomeWithStoppedRuntimeLandsOnSummary() {
        let runtimeIssue = WizardIssue(
            identifier: .daemon, severity: .error, category: .daemon,
            title: "Start driverless remapping", description: "The session keyboard runtime is stopped or not ready.",
            autoFixAction: .restartCommServer, userAction: "Start the keyboard service"
        )
        let next = WizardRouter.nextPage(
            after: .welcome, state: .serviceNotRunning, issues: [runtimeIssue]
        )
        // Welcome is outside the ordered steps, so Get Started reaches the summary.
        XCTAssertEqual(next, .summary)
        XCTAssertEqual(WizardRouter.route(
            state: .serviceNotRunning, issues: [runtimeIssue]
        ), .service)
    }

    func testNextPageFromWelcomeOnHealthySystemFallsBackToSummary() {
        let next = WizardRouter.nextPage(
            after: .welcome,
            state: .active,
            issues: []
        )
        XCTAssertEqual(next, .summary, "With nothing to fix (e.g. forced QA runs), Get Started should land on summary")
    }
}
