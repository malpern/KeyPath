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
                helperInstalled: false, hasSeenWelcome: false, forced: false
            )
        )
    }

    func testSeenWelcomeNeverShowsAgain() {
        XCTAssertFalse(
            WizardWelcomeGate.shouldShowWelcome(
                helperInstalled: false, hasSeenWelcome: true, forced: false
            )
        )
    }

    func testInstalledHelperSkipsWelcome() {
        XCTAssertFalse(
            WizardWelcomeGate.shouldShowWelcome(
                helperInstalled: true, hasSeenWelcome: false, forced: false
            )
        )
    }

    func testForceOverrideAlwaysShowsWelcome() {
        XCTAssertTrue(
            WizardWelcomeGate.shouldShowWelcome(
                helperInstalled: true, hasSeenWelcome: true, forced: true
            )
        )
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

    func testWelcomeIsNotABlockingPage() {
        XCTAssertFalse(
            WizardRouter.isBlockingPage(.welcome, helperInstalled: false, helperNeedsApproval: false)
        )
    }

    func testNextPageFromWelcomeOnFreshInstallGoesToHelper() {
        let next = WizardRouter.nextPage(
            after: .welcome,
            state: .initializing,
            issues: [],
            helperInstalled: false,
            helperNeedsApproval: false
        )
        XCTAssertEqual(next, .helper, "Get Started on a fresh install should route to the helper page")
    }

    func testNextPageFromWelcomeOnHealthySystemFallsBackToSummary() {
        let next = WizardRouter.nextPage(
            after: .welcome,
            state: .active,
            issues: [],
            helperInstalled: true,
            helperNeedsApproval: false
        )
        XCTAssertEqual(next, .summary, "With nothing to fix (e.g. forced QA runs), Get Started should land on summary")
    }
}
