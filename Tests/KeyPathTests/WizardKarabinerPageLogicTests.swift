import XCTest
@testable import KeyPathAppKit
import KeyPathWizardCore

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

    func testReadyStateAlwaysHealthyEvenWithStaleIssues() {
        let staleIssues = [
            makeIssue(.component(.karabinerDriver), category: .installation),
            makeIssue(.component(.launchDaemonServices), category: .installation)
        ]
        XCTAssertFalse(KarabinerPageLogic.hasIssues(systemState: .ready, issues: staleIssues))
        XCTAssertFalse(KarabinerPageLogic.hasIssues(systemState: .active, issues: staleIssues))
    }

    func testNonReadyStateWithoutIssuesIsHealthy() {
        XCTAssertFalse(KarabinerPageLogic.hasIssues(systemState: .serviceNotRunning, issues: []))
    }

    func testNonReadyStateWithIssuesIsUnhealthy() {
        let issues = [makeIssue(.component(.karabinerDriver), category: .installation)]
        XCTAssertTrue(KarabinerPageLogic.hasIssues(systemState: .serviceNotRunning, issues: issues))
    }
}

