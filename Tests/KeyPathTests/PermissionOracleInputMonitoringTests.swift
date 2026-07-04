import KeyPathCore
@testable import KeyPathPermissions
@preconcurrency import XCTest

/// Covers the ADR-006 precedence for KeyPath's OWN Input Monitoring signal
/// (#931): IOHIDCheckAccess is authoritative when granted/denied, and the TCC
/// database is consulted only when the Apple API is inconclusive.
final class PermissionOracleInputMonitoringTests: XCTestCase {
    typealias Status = PermissionOracle.Status

    // MARK: - TCC-fallback gating

    func testGrantedAndDeniedDoNotTriggerTCCFallback() {
        XCTAssertFalse(PermissionOracle.keyPathInputMonitoringNeedsTCCFallback(apiStatus: .granted))
        XCTAssertFalse(PermissionOracle.keyPathInputMonitoringNeedsTCCFallback(apiStatus: .denied))
    }

    func testUnknownAndErrorTriggerTCCFallback() {
        XCTAssertTrue(PermissionOracle.keyPathInputMonitoringNeedsTCCFallback(apiStatus: .unknown))
        XCTAssertTrue(PermissionOracle.keyPathInputMonitoringNeedsTCCFallback(apiStatus: .error("x")))
    }

    // MARK: - Resolution precedence

    func testApiGrantedIsAuthoritativeEvenIfTCCDisagrees() {
        // The macOS 26/27 case: kernel says granted, TCC row is missing/denied.
        let resolved = PermissionOracle.resolveKeyPathInputMonitoring(
            apiStatus: .granted, tccStatus: .denied
        )
        XCTAssertEqual(resolved.status, .granted)
        XCTAssertEqual(resolved.source, "keypath.ax-api+im-api")
        XCTAssertEqual(resolved.confidence, .high)
    }

    func testApiDeniedIsAuthoritative() {
        let resolved = PermissionOracle.resolveKeyPathInputMonitoring(
            apiStatus: .denied, tccStatus: nil
        )
        XCTAssertEqual(resolved.status, .denied)
        XCTAssertEqual(resolved.source, "keypath.ax-api+im-api")
        XCTAssertEqual(resolved.confidence, .high)
    }

    func testUnknownApiFallsBackToTCCWhenAvailable() {
        let resolved = PermissionOracle.resolveKeyPathInputMonitoring(
            apiStatus: .unknown, tccStatus: .granted
        )
        XCTAssertEqual(resolved.status, .granted)
        XCTAssertEqual(resolved.source, "keypath.ax-api+tcc-im")
        XCTAssertEqual(resolved.confidence, .high)
    }

    func testUnknownApiAndNoTCCStaysUnknownLowConfidence() {
        let resolved = PermissionOracle.resolveKeyPathInputMonitoring(
            apiStatus: .unknown, tccStatus: nil
        )
        XCTAssertEqual(resolved.status, .unknown)
        XCTAssertEqual(resolved.source, "keypath.ax-api-only")
        XCTAssertEqual(resolved.confidence, .low)
    }

    // MARK: - blockingIssue treats KeyPath's own IM as soft (#931 reconciliation)

    private func snapshot(
        keyPathAX: Status, keyPathIM: Status, kanataAX: Status, kanataIM: Status
    ) -> PermissionOracle.Snapshot {
        let now = Date()
        return PermissionOracle.Snapshot(
            keyPath: .init(
                accessibility: keyPathAX, inputMonitoring: keyPathIM,
                source: "test", confidence: .high, timestamp: now
            ),
            kanata: .init(
                accessibility: kanataAX, inputMonitoring: kanataIM,
                source: "test", confidence: .high, timestamp: now
            ),
            timestamp: now
        )
    }

    /// Denied KeyPath IM alone must not produce a blocking issue (it powers only
    /// the overlay, not remapping) — consistent with isSystemReady.
    func testDeniedKeyPathInputMonitoringIsNotBlocking() {
        let snap = snapshot(
            keyPathAX: .granted, keyPathIM: .denied, kanataAX: .granted, kanataIM: .granted
        )
        XCTAssertNil(snap.blockingIssue)
        XCTAssertTrue(snap.isSystemReady)
    }

    /// KeyPath's own Accessibility remains a hard blocker.
    func testDeniedKeyPathAccessibilityIsBlocking() {
        let snap = snapshot(
            keyPathAX: .denied, keyPathIM: .granted, kanataAX: .granted, kanataIM: .granted
        )
        XCTAssertNotNil(snap.blockingIssue)
        XCTAssertTrue(snap.blockingIssue?.contains("Accessibility") ?? false)
    }

    /// Kanata's Input Monitoring remains a hard blocker (it drives remapping).
    func testDeniedKanataInputMonitoringIsBlocking() {
        let snap = snapshot(
            keyPathAX: .granted, keyPathIM: .granted, kanataAX: .granted, kanataIM: .denied
        )
        XCTAssertNotNil(snap.blockingIssue)
        XCTAssertFalse(snap.isSystemReady)
    }
}
