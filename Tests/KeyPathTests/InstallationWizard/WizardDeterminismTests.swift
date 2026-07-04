@testable import KeyPathInstallationWizard
import KeyPathWizardCore
@preconcurrency import XCTest

/// Determinism tests: same inputs always produce the same routing output.
@MainActor
final class WizardDeterminismTests: XCTestCase {
    func testSameInputsProduceSamePageEveryTime() {
        let issues = [WizardIssue(
            identifier: .permission(.keyPathInputMonitoring),
            severity: .error,
            category: .permissions,
            title: "IM denied",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]
        let state: WizardSystemState = .missingPermissions(missing: [.keyPathInputMonitoring])

        let first = WizardRouter.route(state: state, issues: issues, helperInstalled: true, helperNeedsApproval: false)
        let second = WizardRouter.route(state: state, issues: issues, helperInstalled: true, helperNeedsApproval: false)

        XCTAssertEqual(first, second, "Routing should be deterministic for identical inputs")
    }

    func testDifferentInputsLeadToDifferentPages() {
        let conflictIssues = [WizardIssue(
            identifier: .conflict(.karabinerGrabberRunning(pid: 123)),
            severity: .error,
            category: .conflicts,
            title: "Conflict",
            description: "",
            autoFixAction: nil,
            userAction: nil
        )]

        let conflictPage = WizardRouter.route(
            state: .conflictsDetected(conflicts: [.karabinerGrabberRunning(pid: 123)]),
            issues: conflictIssues,
            helperInstalled: true,
            helperNeedsApproval: false
        )
        let readyPage = WizardRouter.route(
            state: .active,
            issues: [],
            helperInstalled: true,
            helperNeedsApproval: false
        )

        XCTAssertEqual(conflictPage, .conflicts)
        XCTAssertEqual(readyPage, .summary)
        XCTAssertNotEqual(conflictPage, readyPage)
    }

    /// Regression test for #934: the wizard must have a single, deterministic
    /// initial page (.summary) with no eager navigation to another page before
    /// the first state check completes. Previously the view eagerly navigated
    /// to .helper on setup and then bounced back to .summary once permissions
    /// resolved, causing a visible summary→helper→summary flicker on open.
    func testStateMachineStartsOnSummaryAndResetNavigationReturnsToSummary() {
        let stateMachine = WizardStateMachine()
        XCTAssertEqual(stateMachine.currentPage, .summary, "Fresh state machine must start on summary")

        stateMachine.navigateToPage(.helper)
        XCTAssertEqual(stateMachine.currentPage, .helper)

        stateMachine.resetNavigation()
        XCTAssertEqual(
            stateMachine.currentPage, .summary,
            "resetNavigation() must deterministically return to summary so wizard setup has a single stable starting page"
        )
    }
}
