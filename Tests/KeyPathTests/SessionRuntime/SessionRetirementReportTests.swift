import Foundation
import KeyPathCore
import XCTest

final class SessionRetirementReportTests: XCTestCase {
    private func report(failure: String?, retirement: String? = nil) -> SessionRuntimeReport {
        SessionRuntimeReport(nonce: "owned-launch", pid: 123, uid: 502, state: .failed,
                             accessibility: true, effectiveInputAccess: true, tapActive: false,
                             tcpPort: 37001, inputCount: 0, outputCount: 0, failure: failure,
                             retirementReason: retirement)
    }

    func testCleanupFailureRetainsSleepBoundaryAcrossWorkerReport() throws {
        let value = report(failure: "managed-caps-restoration-pending", retirement: "system-will-sleep")
        let decoded = try JSONDecoder().decode(SessionRuntimeReport.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.failure, "managed-caps-restoration-pending")
        XCTAssertEqual(decoded.recoveryReason, "system-will-sleep")
    }

    func testLegacySleepReportStillIdentifiesRecovery() throws {
        let data = try JSONEncoder().encode(report(failure: "system-will-sleep"))
        let decoded = try JSONDecoder().decode(SessionRuntimeReport.self, from: data)
        XCTAssertNil(decoded.retirementReason)
        XCTAssertEqual(decoded.recoveryReason, "system-will-sleep")
    }

    func testCleanupFailureAloneDoesNotAuthorizeWakeRecovery() {
        XCTAssertEqual(report(failure: "managed-caps-restoration-pending").recoveryReason,
                       "managed-caps-restoration-pending")
        XCTAssertEqual(report(failure: "managed-caps-restoration-pending", retirement: "console-session-changed").recoveryReason,
                       "console-session-changed")
    }
}
