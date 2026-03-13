@testable import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

/// Regression: wizard should not route to “Start Service” when Kanata is running.
@MainActor
final class WizardStateRegressionTests: XCTestCase {
    func testDoubleAdaptKeepsActiveStateWhenKanataRunning() {
        // Build a healthy SystemContext (Kanata running, no blocking issues)
        let ready = PermissionOracle.Status.granted
        let set = PermissionOracle.PermissionSet(
            accessibility: ready,
            inputMonitoring: ready,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
        let perms = PermissionOracle.Snapshot(
            keyPath: set,
            kanata: set,
            timestamp: Date()
        )

        let health = HealthStatus(
            kanataRunning: true,
            karabinerDaemonRunning: true,
            vhidHealthy: true
        )

        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )

        let context = SystemContext(
            permissions: perms,
            services: health,
            conflicts: .init(conflicts: [], canAutoResolve: false),
            components: components,
            helper: HelperStatus(isInstalled: true, version: "1.0.0", isWorking: true),
            system: EngineSystemInfo(macOSVersion: "26.0.1", driverCompatible: true),
            timestamp: Date()
        )

        // Run adapt twice to mimic reopen/open flows
        let first = SystemContextAdapter.adapt(context)
        let second = SystemContextAdapter.adapt(context)

        XCTAssertEqual(first.state, .active)
        XCTAssertEqual(second.state, .active)
        XCTAssertTrue(first.issues.isEmpty)
        XCTAssertTrue(second.issues.isEmpty)
    }

    func testRunningKanataWithoutInputCaptureRoutesToMissingPermissions() {
        let ready = PermissionOracle.Status.granted
        let set = PermissionOracle.PermissionSet(
            accessibility: ready,
            inputMonitoring: ready,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
        let perms = PermissionOracle.Snapshot(
            keyPath: set,
            kanata: set,
            timestamp: Date()
        )

        let health = HealthStatus(
            kanataRunning: true,
            karabinerDaemonRunning: true,
            vhidHealthy: true,
            kanataInputCaptureReady: false,
            kanataInputCaptureIssue: "kanata-cannot-open-built-in-keyboard"
        )

        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: true,
            vhidDeviceInstalled: true,
            vhidDeviceHealthy: true,
            vhidServicesHealthy: true,
            vhidVersionMismatch: false
        )

        let context = SystemContext(
            permissions: perms,
            services: health,
            conflicts: .init(conflicts: [], canAutoResolve: false),
            components: components,
            helper: HelperStatus(isInstalled: true, version: "1.0.0", isWorking: true),
            system: EngineSystemInfo(macOSVersion: "26.0.1", driverCompatible: true),
            timestamp: Date()
        )

        let adapted = SystemContextAdapter.adapt(context)

        XCTAssertEqual(adapted.state, .missingPermissions(missing: [.kanataInputMonitoring]))
        XCTAssertTrue(
            adapted.issues.contains { issue in
                issue.identifier == .permission(.kanataInputMonitoring)
            }
        )
    }
}
