import KeyPathCore
@testable import KeyPathPermissions
@preconcurrency import XCTest

/// Apple Input Monitoring results remain authoritative; unavailable evidence
/// stays unknown without reading protected permission databases.
final class PermissionOracleInputMonitoringTests: XCTestCase {
    typealias Status = PermissionOracle.Status

    func testApiGrantedIsAuthoritative() {
        let resolved = PermissionOracle.resolveKeyPathInputMonitoring(apiStatus: .granted)
        XCTAssertEqual(resolved.status, .granted)
        XCTAssertEqual(resolved.source, "keypath.ax-api+im-api")
        XCTAssertEqual(resolved.confidence, .high)
    }

    func testApiDeniedIsAuthoritative() {
        let resolved = PermissionOracle.resolveKeyPathInputMonitoring(apiStatus: .denied)
        XCTAssertEqual(resolved.status, .denied)
        XCTAssertEqual(resolved.source, "keypath.ax-api+im-api")
        XCTAssertEqual(resolved.confidence, .high)
    }

    func testUnavailableApiStaysUnknownLowConfidence() {
        for status in [Status.unknown, .error("unavailable")] {
            let resolved = PermissionOracle.resolveKeyPathInputMonitoring(apiStatus: status)
            XCTAssertEqual(resolved.status, .unknown)
            XCTAssertEqual(resolved.source, "keypath.ax-api-only")
            XCTAssertEqual(resolved.confidence, .low)
        }
    }

    func testLegacyRuntimeWithoutEffectiveFactsStaysUnknown() {
        let timestamp = Date(timeIntervalSince1970: 123)
        let permissions = PermissionOracle.legacyKanataPermissions(timestamp: timestamp)
        XCTAssertEqual(permissions.accessibility, .unknown)
        XCTAssertEqual(permissions.inputMonitoring, .unknown)
        XCTAssertEqual(permissions.source, "kanata.unknown")
        XCTAssertEqual(permissions.confidence, .low)
        XCTAssertEqual(permissions.timestamp, timestamp)
        XCTAssertFalse(permissions.hasAllPermissions)
    }

    func testSessionReadinessStillRequiresListeningAndPosting() {
        let timestamp = Date()
        for listening in [Status.denied, .unknown, .error("unavailable")] {
            let permissions = PermissionOracle.sessionPermissionSet(
                accessibility: .granted, eventListening: listening,
                eventPosting: .granted, timestamp: timestamp
            )
            XCTAssertEqual(permissions.inputMonitoring, listening)
            XCTAssertFalse(permissions.hasAllPermissions)
        }
        let permissions = PermissionOracle.sessionPermissionSet(
            accessibility: .granted, eventListening: .granted,
            eventPosting: .granted, timestamp: timestamp
        )
        XCTAssertTrue(permissions.hasAllPermissions)
        XCTAssertEqual(permissions.source, "current-process.apple-api.listen-and-post-event")
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
