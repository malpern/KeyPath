@testable import KeyPathAppKit
@testable import KeyPathDaemonLifecycle
@testable import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

/// End-to-end-ish tests that validate the path:
/// SystemContext (InstallerEngine) -> SystemContextAdapter -> WizardIssue severities -> WizardStateInterpreter page status.
@MainActor
final class SystemContextAdapterPermissionSeverityTests: XCTestCase {
    func testKanataUnknownPermissionBecomesWarningIssueAndWarningPageStatus() {
        let now = Date()

        let keyPath = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test",
            confidence: .high,
            timestamp: now
        )

        // Represents "not verified" (e.g., no Full Disk Access to read TCC.db).
        let kanata = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .unknown,
            source: "test",
            confidence: .low,
            timestamp: now
        )

        let permissions = PermissionOracle.Snapshot(keyPath: keyPath, kanata: kanata, timestamp: now)

        let context = SystemContext(
            permissions: permissions,
            services: HealthStatus(kanataRunning: false, karabinerDaemonRunning: true, vhidHealthy: true),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            components: ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: true,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: true,
                launchDaemonServicesHealthy: true,
                vhidServicesHealthy: true,
                vhidVersionMismatch: false
            ),
            helper: HelperStatus(isInstalled: true, version: nil, isWorking: true),
            system: EngineSystemInfo(macOSVersion: "test", driverCompatible: true),
            timestamp: now
        )

        let result = SystemContextAdapter.adapt(context)

        let kanataIMIssue = result.issues.first { $0.identifier == .permission(.kanataInputMonitoring) }
        XCTAssertNotNil(kanataIMIssue, "Adapter should surface a kanata input monitoring issue")
        XCTAssertEqual(kanataIMIssue?.severity, .warning, "Unknown/not-verified kanata permission should be a warning")
        XCTAssertNotNil(kanataIMIssue?.description)
        XCTAssertTrue(kanataIMIssue?.description.localizedCaseInsensitiveContains("not verified") ?? false)
        XCTAssertFalse(
            kanataIMIssue?.description.localizedCaseInsensitiveContains("required") ?? false,
            "Unknown/not verified should not claim permission is required"
        )
        XCTAssertFalse(
            kanataIMIssue?.description.localizedCaseInsensitiveContains("denied") ?? false,
            "Unknown/not verified should not claim permission is denied"
        )

        let interpreter = WizardStateInterpreter()
        let pageStatus = interpreter.getPageStatus(for: .inputMonitoring, in: result.issues)
        XCTAssertEqual(pageStatus, .warning, "Input Monitoring page should show warning when only 'unknown' kanata permission exists")
    }
}
