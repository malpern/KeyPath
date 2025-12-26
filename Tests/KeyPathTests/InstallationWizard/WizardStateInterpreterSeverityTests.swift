@testable import KeyPathAppKit
import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class WizardStateInterpreterSeverityTests: XCTestCase {
    func testPermissionStatusIsWarningForUnknownPermissionIssue() {
        let interpreter = WizardStateInterpreter()

        let issue = WizardIssue(
            identifier: .permission(.kanataInputMonitoring),
            severity: .warning, // represents "unknown / not verified"
            category: .installation,
            title: "Kanata needs Input Monitoring",
            description: "Not verified (grant Full Disk Access to verify).",
            autoFixAction: nil,
            userAction: "Grant Input Monitoring"
        )

        let status = interpreter.getPermissionStatus(.kanataInputMonitoring, in: [issue])
        XCTAssertEqual(status, .warning)
    }

    func testPermissionStatusIsFailedForDeniedPermissionIssue() {
        let interpreter = WizardStateInterpreter()

        let issue = WizardIssue(
            identifier: .permission(.keyPathAccessibility),
            severity: .error,
            category: .installation,
            title: "KeyPath needs Accessibility",
            description: "Grant Accessibility.",
            autoFixAction: nil,
            userAction: "Grant Accessibility"
        )

        let status = interpreter.getPermissionStatus(.keyPathAccessibility, in: [issue])
        XCTAssertEqual(status, .failed)
    }

    func testPageStatusIsWarningWhenOnlyWarningsPresent() {
        let interpreter = WizardStateInterpreter()

        let warning = WizardIssue(
            identifier: .permission(.kanataAccessibility),
            severity: .warning,
            category: .installation,
            title: "Kanata permission not verified",
            description: "Unknown / not verified.",
            autoFixAction: nil,
            userAction: "Grant permission"
        )

        let pageStatus = interpreter.getPageStatus(for: .accessibility, in: [warning])
        XCTAssertEqual(pageStatus, .warning)
    }
}

