@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

final class ServiceStatusEvaluatorActionTests: XCTestCase {
    func testSuccessfulActionUsesFreshRunningObservationOverStaleIssue() {
        let status = ServiceStatusEvaluator.evaluateAfterAction(
            operationSucceeded: true,
            kanataIsRunning: true,
            systemState: .active,
            issues: [staleInputCaptureIssue()]
        )

        XCTAssertEqual(status, .running)
    }

    func testSuccessfulActionStillRequiresFreshRunningObservation() {
        let status = ServiceStatusEvaluator.evaluateAfterAction(
            operationSucceeded: true,
            kanataIsRunning: false,
            systemState: .serviceNotRunning,
            issues: [staleInputCaptureIssue()]
        )

        XCTAssertEqual(status, .stopped)
    }

    func testFailedActionRetainsCurrentIssue() {
        let status = ServiceStatusEvaluator.evaluateAfterAction(
            operationSucceeded: false,
            kanataIsRunning: true,
            systemState: .active,
            issues: [staleInputCaptureIssue()]
        )

        XCTAssertEqual(
            status,
            ServiceProcessStatus.failed(message: "Kanata Isn't Capturing Keyboard Input")
        )
    }

    private func staleInputCaptureIssue() -> WizardIssue {
        WizardIssue(
            identifier: .daemon,
            severity: .error,
            category: .daemon,
            title: "Kanata Isn't Capturing Keyboard Input",
            description: "Captured before the service action",
            autoFixAction: nil,
            userAction: nil
        )
    }
}
