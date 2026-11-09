import KeyPathCore
@testable import KeyPathPermissions
@preconcurrency import XCTest

/// The session worker's key access combines its listen and post grants; the
/// snapshot carries that report as the runtime's single key-access status.
final class PermissionOracleKeyAccessTests: XCTestCase {
    typealias Status = PermissionOracle.Status

    func testKeyAccessUsesListenStatusWhenListeningIsNotGranted() {
        let timestamp = Date()
        for listening in [Status.denied, .unknown, .error("unavailable")] {
            let capabilities = PermissionOracle.sessionCapabilities(
                accessibility: .granted, eventListening: listening,
                eventPosting: .granted, timestamp: timestamp
            )
            XCTAssertEqual(capabilities.keyAccess, listening)
            XCTAssertFalse(capabilities.isReady)
        }
    }

    func testKeyAccessUsesPostStatusOnceListeningIsGranted() {
        let timestamp = Date()
        let ready = PermissionOracle.sessionCapabilities(
            accessibility: .granted, eventListening: .granted,
            eventPosting: .granted, timestamp: timestamp
        )
        XCTAssertTrue(ready.isReady)
        XCTAssertEqual(ready.source, "current-process.apple-api.listen-and-post-event")
        let postDenied = PermissionOracle.sessionCapabilities(
            accessibility: .granted, eventListening: .granted,
            eventPosting: .denied, timestamp: timestamp
        )
        XCTAssertEqual(postDenied.keyAccess, .denied)
        XCTAssertFalse(postDenied.isReady)
    }

    func testCapabilitiesRequireAccessibility() {
        let capabilities = PermissionOracle.sessionCapabilities(
            accessibility: .denied, eventListening: .granted,
            eventPosting: .granted, timestamp: Date()
        )
        XCTAssertFalse(capabilities.isReady)
    }

    func testDeniedAccessibilityIsBlocking() {
        let snap = PermissionOracle.Snapshot.fixture(accessibility: .denied)
        XCTAssertTrue(snap.blockingIssue?.contains(AccessibilityPermissionPresentation.current.name) ?? false)
        XCTAssertFalse(snap.isSystemReady)
    }

    func testDeniedRuntimeKeyAccessIsBlocking() {
        let snap = PermissionOracle.Snapshot.fixture(runtimeKeyAccess: .denied)
        XCTAssertNotNil(snap.blockingIssue)
        XCTAssertFalse(snap.isSystemReady)
    }
}
