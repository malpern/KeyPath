@testable import KeyPathAppKit
@testable import KeyPathPermissions
@preconcurrency import XCTest

@MainActor
final class PermissionGateEvaluationTests: XCTestCase {
    func testKanataUnknownClassifiesAsNotVerifiedNotBlocking() {
        let now = Date()
        let snap = PermissionOracle.Snapshot(
            keyPath: .init(
                accessibility: .granted,
                inputMonitoring: .granted,
                source: "test",
                confidence: .high,
                timestamp: now
            ),
            kanata: .init(
                accessibility: .unknown,
                inputMonitoring: .unknown,
                source: "test",
                confidence: .low,
                timestamp: now
            ),
            timestamp: now
        )

        let eval = PermissionGate.evaluate(snap, for: .keyboardRemapping)
        XCTAssertTrue(eval.missingKeyPath.isEmpty)
        XCTAssertTrue(eval.kanataBlocking.isEmpty)
        XCTAssertEqual(eval.kanataNotVerified, [.accessibility, .inputMonitoring])
    }

    func testKanataDeniedClassifiesAsBlocking() {
        let now = Date()
        let snap = PermissionOracle.Snapshot(
            keyPath: .init(
                accessibility: .granted,
                inputMonitoring: .granted,
                source: "test",
                confidence: .high,
                timestamp: now
            ),
            kanata: .init(
                accessibility: .denied,
                inputMonitoring: .denied,
                source: "test",
                confidence: .high,
                timestamp: now
            ),
            timestamp: now
        )

        let eval = PermissionGate.evaluate(snap, for: .keyboardRemapping)
        XCTAssertTrue(eval.missingKeyPath.isEmpty)
        XCTAssertEqual(eval.kanataBlocking, [.accessibility, .inputMonitoring])
        XCTAssertTrue(eval.kanataNotVerified.isEmpty)
    }
}
