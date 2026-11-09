@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

/// A runtime issue of error severity must keep the service row from rendering
/// as running, while warning-severity daemon issues (a status-check timeout)
/// must not block it.
final class ServiceStatusEvaluatorBlockingIssueTests: XCTestCase {
    func testDaemonError_serviceStatusIsFailed_notRunning() {
        let issue = WizardIssue(
            identifier: .daemon, severity: .error, category: .daemon,
            title: "Start driverless remapping", description: "", autoFixAction: .restartCommServer, userAction: nil
        )
        let status = ServiceStatusEvaluator.evaluate(
            kanataIsRunning: true,
            systemState: .serviceNotRunning,
            issues: [issue]
        )
        guard case let .failed(message) = status else {
            return XCTFail("A daemon error should render the service as failed, not running")
        }
        XCTAssertEqual(message, "Start driverless remapping")
    }

    func testTimeoutWarning_doesNotBlockServiceStatus() {
        let warning = WizardIssue(
            identifier: .daemon, severity: .warning, category: .daemon,
            title: "System check timed out", description: "", autoFixAction: nil, userAction: nil
        )
        XCTAssertNil(ServiceStatusEvaluator.blockingIssueMessage(from: [warning]))
    }
}
