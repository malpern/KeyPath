@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

/// #624: when kanata is running but not capturing input, the wizard must
/// attribute the failure honestly — a grab failure (driver crash, another app
/// holding the keyboard, not root) is NOT a missing permission and is fixed by
/// restarting, not by regranting Input Monitoring.
final class SystemInspectorInputCaptureTests: XCTestCase {
    private func context(inputCaptureIssue: String?, servicesHealthy: Bool = true) -> SystemContext {
        SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: servicesHealthy,
            kanataInputCaptureReady: false,
            kanataInputCaptureIssue: inputCaptureIssue,
            componentsInstalled: true
        ).build()
    }

    // MARK: - State routing

    func testGrabFailure_routesToService_notPermissions() {
        let state = SystemInspector.determineState(context(inputCaptureIssue: ServiceHealthChecker.inputCaptureGrabFailureReason))
        XCTAssertEqual(state, .serviceNotRunning, "A grab failure must not be misrouted to the permissions page")
    }

    func testAuthoritativeReason_routesToService() {
        // A free-text InputGrab reason from kanata is also a grab failure.
        let state = SystemInspector.determineState(context(inputCaptureIssue: "another process has exclusive grab"))
        XCTAssertEqual(state, .serviceNotRunning)
    }

    func testBuiltInKeyboardPermission_staysOnPermissions() {
        let state = SystemInspector.determineState(context(inputCaptureIssue: ServiceHealthChecker.inputCaptureBuiltInKeyboardReason))
        XCTAssertEqual(state, .missingPermissions(missing: [.kanataInputMonitoring]))
    }

    func testNilReason_routesToService_notPermissions() {
        // An unknown/unpopulated reason must never be blamed on permissions.
        let state = SystemInspector.determineState(context(inputCaptureIssue: nil))
        XCTAssertEqual(state, .serviceNotRunning)
    }

    // MARK: - Issue card

    func testGrabFailure_issueIsHonest_noFalseAutofix() {
        let issues = SystemInspector.generateIssues(context(inputCaptureIssue: ServiceHealthChecker.inputCaptureGrabFailureReason))
        guard let issue = issues.first(where: { $0.identifier == .daemon }) else {
            return XCTFail("Expected an honest daemon issue for a grab failure")
        }
        XCTAssertEqual(issue.title, "Kanata Isn't Capturing Keyboard Input")
        // No auto-fix: the existing recipes don't actually bounce the wedged
        // kanata process, so a one-click "Restart" here would be a false remedy.
        XCTAssertNil(issue.autoFixAction)
        XCTAssertEqual(issue.category, .daemon)
        XCTAssertFalse(
            issues.contains { $0.identifier == .permission(.kanataInputMonitoring) },
            "A grab failure must not be surfaced as a missing Input Monitoring permission"
        )
    }

    func testVHIDDriverNotActivated_issueRequiresManualApproval() {
        let issues = SystemInspector.generateIssues(
            context(
                inputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason,
                servicesHealthy: false
            )
        )
        guard let issue = issues.first(where: { $0.identifier == .daemon }) else {
            return XCTFail("Expected a daemon issue for inactive VHID DriverKit state")
        }
        XCTAssertEqual(issue.title, "Kanata Isn't Capturing Keyboard Input")
        XCTAssertNil(issue.autoFixAction)
        XCTAssertEqual(
            issue.userAction,
            "Open System Settings → General → Login Items & Extensions → Driver Extensions, enable Karabiner-VirtualHIDDevice, then retry repair"
        )
        XCTAssertTrue(issue.description.contains("not activated"))
    }

    func testStaleVHIDDriverNotActivatedIssue_afterVHIDHealthyCanRepair() {
        let issues = SystemInspector.generateIssues(
            context(inputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason)
        )
        guard let issue = issues.first(where: { $0.identifier == .daemon }) else {
            return XCTFail("Expected a daemon issue for stale inactive VHID DriverKit state")
        }
        XCTAssertEqual(issue.title, "Kanata Isn't Capturing Keyboard Input")
        XCTAssertEqual(issue.autoFixAction, .installRequiredRuntimeServices)
        XCTAssertEqual(issue.userAction, "Restart the keyboard service from Settings → Status (or quit and reopen KeyPath)")
        XCTAssertTrue(issue.description.contains("VirtualHID services now look healthy"))
    }

    // MARK: - Service status must not lie green on a grab failure

    func testGrabFailure_serviceStatusIsFailed_notRunning() {
        // The Service page must reflect the grab failure even though the process
        // is up + TCP-reachable (the #624 dishonesty — and the trap of routing
        // here without making the status honest).
        let issues = SystemInspector.generateIssues(context(inputCaptureIssue: ServiceHealthChecker.inputCaptureGrabFailureReason))
        let status = ServiceStatusEvaluator.evaluate(
            kanataIsRunning: true,
            systemState: .serviceNotRunning,
            issues: issues
        )
        guard case let .failed(message) = status else {
            return XCTFail("Grab failure should render the service as failed, not running")
        }
        XCTAssertEqual(message, "Kanata Isn't Capturing Keyboard Input")
    }

    func testTimeoutWarning_doesNotBlockServiceStatus() {
        // A warning-severity daemon issue (status-check timeout) must NOT mark the
        // service failed — only error/critical grab failures do.
        let warning = WizardIssue(
            identifier: .daemon, severity: .warning, category: .daemon,
            title: "System check timed out", description: "", autoFixAction: nil, userAction: nil
        )
        XCTAssertNil(ServiceStatusEvaluator.blockingIssueMessage(from: [warning]))
    }

    func testAuthoritativeReason_surfacedInDescription() throws {
        let issues = SystemInspector.generateIssues(context(inputCaptureIssue: "not running as root"))
        let issue = issues.first { $0.identifier == .daemon }
        XCTAssertNotNil(issue)
        XCTAssertTrue(try XCTUnwrap(issue?.description.contains("not running as root")), "kanata's actual reason should be surfaced")
    }

    func testBuiltInKeyboard_keepsPermissionIssue() {
        let issues = SystemInspector.generateIssues(context(inputCaptureIssue: ServiceHealthChecker.inputCaptureBuiltInKeyboardReason))
        XCTAssertTrue(issues.contains { $0.identifier == .permission(.kanataInputMonitoring) })
        XCTAssertFalse(issues.contains { $0.identifier == .daemon && $0.title.contains("Capturing") })
    }

    // MARK: - Helpers

    func testIsInputCapturePermissionReason() {
        XCTAssertTrue(SystemInspector.isInputCapturePermissionReason(ServiceHealthChecker.inputCaptureBuiltInKeyboardReason))
        XCTAssertFalse(SystemInspector.isInputCapturePermissionReason(ServiceHealthChecker.inputCaptureGrabFailureReason))
        XCTAssertFalse(SystemInspector.isInputCapturePermissionReason("another process has exclusive grab"))
        XCTAssertFalse(SystemInspector.isInputCapturePermissionReason(nil))
    }
}
