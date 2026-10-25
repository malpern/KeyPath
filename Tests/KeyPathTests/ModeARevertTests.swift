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

    func testAdapterRoutesToPermissionsWhenPermissionRejected() {
        let context = makeContext(
            kanataRunning: false,
            kanataPermissionRejected: true,
            permissionsGranted: true
        )

        let result = SystemStateResult.projecting(context)

        XCTAssertEqual(
            result.state, .missingPermissions(missing: [.kanataAccessibility]),
            "Adapter must route to missingPermissions when kanataPermissionRejected is true"
        )
    }

    func testAdapterIssuesContainPermissionWhenRejected() {
        let context = makeContext(
            kanataRunning: false,
            kanataPermissionRejected: true,
            permissionsGranted: true
        )

        let result = SystemStateResult.projecting(context)

        let axIssue = result.issues.first { $0.identifier == .permission(.kanataAccessibility) }
        XCTAssertNotNil(axIssue, "Issues must include kanataAccessibility permission issue")
        XCTAssertEqual(axIssue?.severity, .error)
        XCTAssertEqual(axIssue?.category, .permissions)
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
        let health = HealthStatus(backend: .driverKit,
                                  kanataRunning: false,
                                  karabinerDaemonRunning: true,
                                  vhidHealthy: true)
        XCTAssertFalse(health.kanataPermissionRejected)
    }

    func testHealthStatusPermissionRejectedPropagates() {
        let health = HealthStatus(backend: .driverKit,
                                  kanataRunning: false,
                                  karabinerDaemonRunning: true,
                                  vhidHealthy: true,
                                  kanataPermissionRejected: true)
        XCTAssertTrue(health.kanataPermissionRejected)
    }

    // MARK: - SystemSnapshot.blockingIssues

    func testBlockingIssuesEmitPermissionWhenRejected() {
        let snapshot = makeSnapshot(kanataRunning: false, kanataPermissionRejected: true)

        let permIssues = snapshot.blockingIssues.filter {
            if case let .permissionMissing(app, perm, _) = $0 {
                return app == "Kanata" && perm == "Accessibility"
            }
            return false
        }
        XCTAssertFalse(permIssues.isEmpty, "blockingIssues must contain Kanata Accessibility permission issue")

        let serviceIssues = snapshot.blockingIssues.filter {
            if case let .serviceNotRunning(name, _) = $0 {
                return name == "Kanata Service"
            }
            return false
        }
        XCTAssertTrue(serviceIssues.isEmpty, "blockingIssues must NOT contain serviceNotRunning when permission was rejected")
    }

    func testBlockingIssuesEmitServiceNotRunningWithoutRejection() {
        let snapshot = makeSnapshot(kanataRunning: false, kanataPermissionRejected: false)

        let serviceIssues = snapshot.blockingIssues.filter {
            if case let .serviceNotRunning(name, _) = $0 {
                return name == "Kanata Service"
            }
            return false
        }
        XCTAssertFalse(serviceIssues.isEmpty, "blockingIssues must contain serviceNotRunning when no permission rejection")
    }

    func testSessionStoppedWithLegacyRejectionUsesCurrentRuntimeEvidence() {
        let snapshot = makeSnapshot(kanataRunning: false, kanataPermissionRejected: true, backend: .session)
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
            backend: .session, accessibility: .denied
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

        let keyPath = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        let kanata = PermissionOracle.PermissionSet(
            accessibility: status,
            inputMonitoring: status,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        return SystemContext(
            permissions: PermissionOracle.Snapshot(keyPath: keyPath, kanata: kanata, timestamp: now, backend: .driverKit),
            services: HealthStatus(backend: .driverKit,
                                   kanataRunning: kanataRunning,
                                   karabinerDaemonRunning: true,
                                   vhidHealthy: true,
                                   kanataInputCaptureReady: true,
                                   kanataPermissionRejected: kanataPermissionRejected),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            components: ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: true,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: true,
                vhidServicesHealthy: true,
                vhidVersionMismatch: false
            ),
            helper: HelperStatus(isInstalled: true, version: nil, isWorking: true),
            system: EngineSystemInfo(macOSVersion: "test", driverCompatible: true),
            timestamp: now
        )
    }

    private func makeSnapshot(
        kanataRunning: Bool,
        kanataPermissionRejected: Bool,
        backend: KanataRuntimeBackend = .driverKit,
        accessibility: PermissionOracle.Status = .granted
    ) -> SystemSnapshot {
        let now = Date()
        let keyPath = PermissionOracle.PermissionSet(
            accessibility: accessibility,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )
        let kanata = PermissionOracle.PermissionSet(
            accessibility: accessibility,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        return SystemSnapshot(
            permissions: PermissionOracle.Snapshot(keyPath: keyPath, kanata: kanata, timestamp: now, backend: backend),
            components: ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: true,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: true,
                vhidServicesHealthy: true,
                vhidVersionMismatch: false
            ),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            health: HealthStatus(backend: backend,
                                 kanataRunning: kanataRunning,
                                 karabinerDaemonRunning: true,
                                 vhidHealthy: true,
                                 kanataInputCaptureReady: true,
                                 kanataPermissionRejected: kanataPermissionRejected),
            helper: HelperStatus(isInstalled: true, version: nil, isWorking: true),
            compatibility: SystemCompatibilityStatus(macOSVersion: "test", driverCompatible: true),
            timestamp: now
        )
    }
}
