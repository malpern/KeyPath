import XCTest
@testable import KeyPath

final class SystemRequirementsCheckerTests: XCTestCase {
    func testCheckAllRequirementsProducesReport() async {
        let checker = SystemRequirementsChecker()
        let report = await checker.checkAllRequirements()
        XCTAssertFalse(report.results.isEmpty)
        XCTAssertFalse(report.summary.isEmpty)
        // Should include at least system version and architecture rows
        XCTAssertTrue(report.results.contains { $0.requirement == .systemVersion })
        XCTAssertTrue(report.results.contains { $0.requirement == .architecture })
        // Overall status must align with blocking issues presence
        if report.blockingIssues.isEmpty {
            switch report.overallStatus { case .allSatisfied, .hasWarnings: break; default: XCTFail("Unexpected overall status") }
        } else {
            switch report.overallStatus { case .hasBlockingIssues, .systemError: break; default: XCTFail("Expected blocking status") }
        }
    }
}

