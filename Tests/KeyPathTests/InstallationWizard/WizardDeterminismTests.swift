@testable import KeyPathInstallationWizard
import KeyPathWizardCore
@preconcurrency import XCTest

/// Determinism tests: same inputs always produce the same routing output.
@MainActor
final class WizardDeterminismTests: XCTestCase {
    func testSameInputsProduceSamePageEveryTime() {
        let issues = [WizardIssue(
            identifier: .permission(.runtimeKeyAccess),
            severity: .error,
            category: .permissions,
            title: "Runtime key access denied",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let state: WizardSystemState = .missingPermissions(missing: [.runtimeKeyAccess])

        let first = WizardRouter.route(state: state, issues: issues)
        let second = WizardRouter.route(state: state, issues: issues)

        XCTAssertEqual(first, second, "Routing should be deterministic for identical inputs")
    }

    func testDifferentInputsLeadToDifferentPages() {
        let permissionIssues = [WizardIssue(
            identifier: .permission(.keyPathAccessibility),
            severity: .error,
            category: .permissions,
            title: "Accessibility denied",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]

        let permissionPage = WizardRouter.route(
            state: .missingPermissions(missing: [.keyPathAccessibility]),
            issues: permissionIssues
        )
        let readyPage = WizardRouter.route(
            state: .active,
            issues: []
        )

        XCTAssertEqual(permissionPage, .accessibility)
        XCTAssertEqual(readyPage, .summary)
        XCTAssertNotEqual(permissionPage, readyPage)
    }

    /// Regression test for #934: the wizard must have a single, deterministic
    /// initial page (.summary) with no eager navigation to another page before
    /// the first state check completes. Previously the view eagerly navigated
    /// to .helper on setup and then bounced back to .summary once permissions
    /// resolved, causing a visible summary→helper→summary flicker on open.
    func testStateMachineStartsOnSummaryAndResetNavigationReturnsToSummary() {
        let stateMachine = WizardStateMachine()
        XCTAssertEqual(stateMachine.currentPage, .summary, "Fresh state machine must start on summary")

        stateMachine.navigateToPage(.accessibility)
        XCTAssertEqual(stateMachine.currentPage, .accessibility)

        stateMachine.resetNavigation()
        XCTAssertEqual(
            stateMachine.currentPage, .summary,
            "resetNavigation() must deterministically return to summary so wizard setup has a single stable starting page"
        )
    }
}
