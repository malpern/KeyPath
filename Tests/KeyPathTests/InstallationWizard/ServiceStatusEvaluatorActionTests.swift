@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

final class ServiceStatusEvaluatorActionTests: XCTestCase {
    func testSuccessfulActionUsesFreshRunningObservationOverStaleIssue() {
        let status = ServiceStatusEvaluator.evaluateAfterAction(
            operationSucceeded: true,
            kanataIsRunning: true,
            systemState: .active,
            issuesBeforeAction: [staleInputCaptureIssue()]
        )

        XCTAssertEqual(status, .running)
    }

    func testSuccessfulActionStillRequiresFreshRunningObservation() {
        let status = ServiceStatusEvaluator.evaluateAfterAction(
            operationSucceeded: true,
            kanataIsRunning: false,
            systemState: .serviceNotRunning,
            issuesBeforeAction: [staleInputCaptureIssue()]
        )

        XCTAssertEqual(status, .stopped)
    }

    func testSuccessfulActionRetainsPermissionIssue() {
        let permissionIssue = WizardIssue(
            identifier: .permission(.kanataInputMonitoring),
            severity: .error,
            category: .permissions,
            title: "Input Monitoring permission required",
            description: "Permission remains denied",
            autoFixAction: nil,
            userAction: nil
        )

        let status = ServiceStatusEvaluator.evaluateAfterAction(
            operationSucceeded: true,
            kanataIsRunning: true,
            systemState: .active,
            issuesBeforeAction: [permissionIssue]
        )

        XCTAssertEqual(
            status,
            ServiceProcessStatus.failed(message: "Input Monitoring permission required")
        )
    }

    func testFailedActionRetainsCurrentIssue() {
        let status = ServiceStatusEvaluator.evaluateAfterAction(
            operationSucceeded: false,
            kanataIsRunning: true,
            systemState: .active,
            issuesBeforeAction: [staleInputCaptureIssue()]
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
