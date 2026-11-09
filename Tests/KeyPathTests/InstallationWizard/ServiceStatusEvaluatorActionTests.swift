import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

final class ServiceStatusEvaluatorActionTests: XCTestCase {
    func testObservedRunningRuntimeSupersedesStaleStartInstruction() {
        let issue = WizardIssue(
            identifier: .daemon, severity: .error, category: .daemon,
            title: "Start driverless remapping", description: "Runtime was stopped",
            autoFixAction: .restartCommServer, userAction: "Start the keyboard service"
        )
        XCTAssertEqual(ServiceStatusEvaluator.evaluateObservedRuntime(
            runtimeStatus: .running(pid: 42), systemState: .serviceNotRunning, issues: [issue]
        ), .running)
        XCTAssertEqual(ServiceStatusEvaluator.evaluateObservedRuntime(
            runtimeStatus: .stopped, systemState: .serviceNotRunning, issues: [issue]
        ), .stopped)
    }

    func testObservedRunningRuntimeRetainsActualInputCaptureFailure() {
        XCTAssertEqual(ServiceStatusEvaluator.evaluateObservedRuntime(
            runtimeStatus: .running(pid: 42), systemState: .active, issues: [staleInputCaptureIssue()]
        ), .failed(message: "Kanata Isn't Capturing Keyboard Input"))
    }

    func testRuntimeKeyAccessIssueAsksForRelaunch() {
        let issue = WizardIssue(
            identifier: .permission(.runtimeKeyAccess), severity: .error,
            category: .permissions, title: "Keyboard access still needs approval",
            description: "Current worker cannot read keyboard events",
            autoFixAction: nil, userAction: nil
        )
        XCTAssertEqual(
            ServiceStatusEvaluator.blockingIssueMessage(from: [issue]),
            "Quit and reopen KeyPath so it can use \(AccessibilityPermissionPresentation.current.name)."
        )
        XCTAssertEqual(
            ServiceStatusEvaluator.evaluateAfterAction(
                operationSucceeded: false, kanataIsRunning: false,
                systemState: .missingPermissions(missing: [.runtimeKeyAccess]), issues: [issue]
            ),
            .stopped
        )
    }

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
        XCTAssertTrue(
            ServiceStatusEvaluator.didExhaustTransientStatus(
                runtimeStatus: .stopped,
                isInTransientStartupWindow: true,
                completedAttempts: ServiceStatusEvaluator.transientRefreshAttemptLimit
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
        XCTAssertFalse(
            ServiceStatusEvaluator.didExhaustTransientStatus(
                runtimeStatus: .running(pid: 42),
                isInTransientStartupWindow: true,
                completedAttempts: ServiceStatusEvaluator.transientRefreshAttemptLimit
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
            identifier: .permission(.runtimeKeyAccess),
            severity: .error,
            category: .permissions,
            title: "Keyboard access still needs approval",
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
