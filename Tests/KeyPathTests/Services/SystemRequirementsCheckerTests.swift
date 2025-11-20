@testable import KeyPathAppKit
import XCTest

final class SystemRequirementsCheckerTests: XCTestCase {
    func testReportFlagsMissingKanataExecutable() {
        let checker = SystemRequirementsChecker()
        let results: [SystemRequirementsChecker.RequirementCheckResult] = [
            .init(
                requirement: .kanataExecution,
                status: .missing,
                details: "Kanata executable not found",
                actionRequired: "Install Kanata"
            ),
            .init(
                requirement: .logDirectory,
                status: .satisfied,
                details: "Log directory exists",
                actionRequired: nil
            )
        ]

        let report = checker.makeReport(results: results, startedAt: Date())

        XCTAssertEqual(report.overallStatus, .hasBlockingIssues)
        XCTAssertTrue(report.requiresInstallation)
        XCTAssertFalse(report.requiresPermissions)
        XCTAssertEqual(report.blockingIssues.count, 1)
        XCTAssertEqual(report.summary, "1 critical requirement(s) not met. KeyPath cannot run until these are resolved.")
    }

    func testReportDetectsMissingPermissions() {
        let checker = SystemRequirementsChecker()
        let results: [SystemRequirementsChecker.RequirementCheckResult] = [
            .init(
                requirement: .accessibilityPermissions,
                status: .missing,
                details: "Accessibility permissions missing",
                actionRequired: "Grant permissions"
            ),
            .init(
                requirement: .kanataExecution,
                status: .satisfied,
                details: "Kanata ready",
                actionRequired: nil
            )
        ]

        let report = checker.makeReport(results: results, startedAt: Date())

        XCTAssertEqual(report.overallStatus, .hasBlockingIssues)
        XCTAssertTrue(report.requiresPermissions)
    }
}
