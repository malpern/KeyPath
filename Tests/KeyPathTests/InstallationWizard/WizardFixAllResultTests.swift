@testable import KeyPathAppKit
import KeyPathWizardCore
@preconcurrency import XCTest

final class WizardFixAllResultTests: XCTestCase {
    func testEvaluateReturnsSuccessWhenActiveAndNoIssues() {
        let result = FixAllResult.evaluate(
            initialIssues: [],
            finalIssues: [],
            finalState: .active,
            steps: []
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.remainingIssueIDs.isEmpty)
    }

    func testEvaluateReturnsPartialWhenIssuesRemain() {
        let initialIssues = [
            makeIssue(.component(.kanataBinaryMissing)),
            makeIssue(.component(.kanataService))
        ]
        let finalIssues = [makeIssue(.component(.kanataService))]
        let steps = [FixStepResult(step: .fastRestart, success: true, detail: nil)]

        let result = FixAllResult.evaluate(
            initialIssues: initialIssues,
            finalIssues: finalIssues,
            finalState: .ready,
            steps: steps
        )

        XCTAssertEqual(result.status, .partial)
        XCTAssertTrue(result.remainingIssueIDs.contains(.component(.kanataService)))
    }

    func testEvaluateReturnsFailedWhenNothingImproved() {
        let initialIssues = [makeIssue(.component(.kanataService))]
        let finalIssues = [makeIssue(.component(.kanataService))]
        let steps = [FixStepResult(step: .fastRestart, success: false, detail: "timeout")]

        let result = FixAllResult.evaluate(
            initialIssues: initialIssues,
            finalIssues: finalIssues,
            finalState: .serviceNotRunning,
            steps: steps
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.remainingIssueIDs.contains(.component(.kanataService)))
    }
}

private func makeIssue(_ identifier: IssueIdentifier) -> WizardIssue {
    WizardIssue(
        identifier: identifier,
        severity: .error,
        category: .installation,
        title: "test",
        description: "test",
        autoFixAction: nil,
        userAction: nil
    )
}
