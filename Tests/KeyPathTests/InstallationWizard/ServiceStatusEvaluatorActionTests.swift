@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

final class ServiceStatusEvaluatorActionTests: XCTestCase {
    func testTransientStartingStatusRetriesUntilAttemptLimit() {
        XCTAssertTrue(
            ServiceStatusEvaluator.shouldRetryTransientStatus(
                runtimeStatus: .starting,
                isInTransientStartupWindow: false,
                completedAttempts: 1
            )
        )
        XCTAssertFalse(
            ServiceStatusEvaluator.shouldRetryTransientStatus(
                runtimeStatus: .starting,
                isInTransientStartupWindow: false,
                completedAttempts: ServiceStatusEvaluator.transientRefreshAttemptLimit
            )
        )
    }

    func testStoppedStatusRetriesOnlyInsideTransientStartupWindow() {
        XCTAssertTrue(
            ServiceStatusEvaluator.shouldRetryTransientStatus(
                runtimeStatus: .stopped,
                isInTransientStartupWindow: true,
                completedAttempts: 1
            )
        )
        XCTAssertFalse(
            ServiceStatusEvaluator.shouldRetryTransientStatus(
                runtimeStatus: .stopped,
                isInTransientStartupWindow: false,
                completedAttempts: 1
            )
        )
    }

    func testSettledRuntimeStatusDoesNotRetry() {
        XCTAssertFalse(
            ServiceStatusEvaluator.shouldRetryTransientStatus(
                runtimeStatus: .running(pid: 42),
                isInTransientStartupWindow: true,
                completedAttempts: 1
            )
        )
        XCTAssertFalse(
            ServiceStatusEvaluator.shouldRetryTransientStatus(
                runtimeStatus: .failed(reason: "boom"),
                isInTransientStartupWindow: true,
                completedAttempts: 1
            )
        )
    }

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

    func testSuccessfulActionSupersedesPreActionPermissionIssue() {
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
            issues: [permissionIssue]
        )

        XCTAssertEqual(status, .running)
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
