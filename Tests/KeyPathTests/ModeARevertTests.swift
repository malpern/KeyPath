@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

/// Historical Mode A (LaunchDaemon subprocess) classifiers plus session evidence behavior.
/// Validates that the feature flag correctly gates split runtime paths
/// and that permission rejection detection works end-to-end.
@MainActor
final class ModeARevertTests: XCTestCase {
    // MARK: - Permission Rejection Detection via SystemStateResult Projection

    func testAdapterIgnoresLegacyDaemonRejectionAndRequestsRuntimeStart() {
        let context = makeContext(
            kanataRunning: false,
            kanataPermissionRejected: true,
            permissionsGranted: true
        )

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(
            result.state, .serviceNotRunning,
            "A historical daemon rejection must not override granted session capabilities"
        )
        XCTAssertFalse(result.issues.contains { $0.identifier.isPermission })
        XCTAssertEqual(result.issues.first { $0.identifier == .daemon }?.autoFixAction, .startSessionRuntime)
    }

    func testAdapterDoesNotEmitRuntimeIssueWhenPermissionRejected() {
        let context = makeContext(
            kanataRunning: false,
            kanataPermissionRejected: true,
            permissionsGranted: true
        )

        let result = SystemStateResult.projecting(context)

        let runtimeIssue = result.issues.first { $0.identifier == .component(.keyPathRuntime) }
        XCTAssertNil(
            runtimeIssue,
            "Should NOT emit 'KeyPath Runtime Not Running' when the real cause is a permission rejection"
        )
    }

    func testAdapterRoutesToServiceNotRunningWithoutPermissionRejection() {
        let context = makeContext(
            kanataRunning: false,
            kanataPermissionRejected: false,
            permissionsGranted: true
        )

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(
            result.state, .serviceNotRunning,
            "Without permission rejection, adapter should report serviceNotRunning"
        )
    }

    func testAdapterRoutesToActiveWhenKanataRunning() {
        let context = makeContext(
            kanataRunning: true,
            kanataPermissionRejected: false,
            permissionsGranted: true
        )

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(result.state, .active)
    }

    // MARK: - HealthStatus kanataPermissionRejected propagation

    func testHealthStatusPermissionRejectedDefaultsFalse() {
        let health = HealthStatus(kanataRunning: false)
        XCTAssertFalse(health.kanataPermissionRejected)
    }

    func testHealthStatusPermissionRejectedPropagates() {
        let health = HealthStatus(kanataRunning: false,
                                  kanataPermissionRejected: true)
        XCTAssertTrue(health.kanataPermissionRejected)
    }

    // MARK: - SystemSnapshot.blockingIssues

    func testSessionStoppedWithLegacyRejectionUsesCurrentRuntimeEvidence() {
        let snapshot = makeSnapshot(kanataRunning: false, kanataPermissionRejected: true)
        XCTAssertTrue(snapshot.blockingIssues.contains {
            if case .componentUnhealthy(name: "Session keyboard runtime", autoFix: true) = $0 { return true }
            return false
        })
        XCTAssertFalse(snapshot.blockingIssues.contains {
            if case .permissionMissing = $0 { return true }
            return false
        }, "Historical daemon rejection must not override granted session capabilities")
    }

    func testSessionDeniedCapabilitiesReportKeyPathPermissionSubject() {
        let snapshot = makeSnapshot(
            kanataRunning: false, kanataPermissionRejected: false,
            accessibility: .denied
        )
        XCTAssertFalse(snapshot.isReady)
        XCTAssertTrue(snapshot.blockingIssues.contains {
            if case let .permissionMissing(app, _, _) = $0 { return app == "KeyPath" }
            return false
        })
    }

    // MARK: - Helpers

    private func makeContext(
        kanataRunning: Bool,
        kanataPermissionRejected: Bool,
        permissionsGranted: Bool
    ) -> SystemContext {
        let now = Date()
        let status: PermissionOracle.Status = permissionsGranted ? .granted : .denied

        return SystemContext(
            permissions: PermissionOracle.Snapshot.fixture(runtimeKeyAccess: status, timestamp: now),
            services: HealthStatus(kanataRunning: kanataRunning,
                                   kanataInputCaptureReady: true,
                                   kanataPermissionRejected: kanataPermissionRejected),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            components: ComponentStatus(
                kanataBinaryInstalled: true
            ),
            system: EngineSystemInfo(macOSVersion: "test"),
            timestamp: now
        )
    }

    private func makeSnapshot(
        kanataRunning: Bool,
        kanataPermissionRejected: Bool,
        accessibility: PermissionOracle.Status = .granted
    ) -> SystemSnapshot {
        let now = Date()
        return SystemSnapshot(
            permissions: PermissionOracle.Snapshot.fixture(accessibility: accessibility, timestamp: now),
            components: ComponentStatus(
                kanataBinaryInstalled: true
            ),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            health: HealthStatus(kanataRunning: kanataRunning,
                                 kanataInputCaptureReady: true,
                                 kanataPermissionRejected: kanataPermissionRejected),
            compatibility: SystemCompatibilityStatus(macOSVersion: "test"),
            timestamp: now
        )
    }
}
