@testable import KeyPathAppKit
import KeyPathWizardCore
import XCTest

final class WizardKarabinerPageLogicTests: XCTestCase {
    private func makeIssue(_ id: IssueIdentifier, category: WizardIssue.IssueCategory) -> WizardIssue {
        WizardIssue(
            identifier: id,
            severity: .error,
            category: category,
            title: "t",
            description: "d",
            autoFixAction: nil,
            userAction: nil
        )
    }

    func testReadyStateRespectsIssues() {
        let staleIssues = [
            makeIssue(.component(.karabinerDriver), category: .installation),
            makeIssue(.component(.launchDaemonServices), category: .installation)
        ]
        XCTAssertTrue(KarabinerPageLogic.hasIssues(systemState: .ready, issues: staleIssues))
        XCTAssertTrue(KarabinerPageLogic.hasIssues(systemState: .active, issues: staleIssues))
    }

    func testNonReadyStateWithoutIssuesIsHealthy() {
        XCTAssertFalse(KarabinerPageLogic.hasIssues(systemState: .serviceNotRunning, issues: []))
    }

    func testNonReadyStateWithIssuesIsUnhealthy() {
        let issues = [makeIssue(.component(.karabinerDriver), category: .installation)]
        XCTAssertTrue(KarabinerPageLogic.hasIssues(systemState: .serviceNotRunning, issues: issues))
    }
}
