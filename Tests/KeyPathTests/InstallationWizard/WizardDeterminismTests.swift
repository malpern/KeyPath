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
}
