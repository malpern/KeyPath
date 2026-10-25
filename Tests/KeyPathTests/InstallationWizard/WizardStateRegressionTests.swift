@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
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
            timestamp: Date(), backend: .driverKit
        )

        let health = HealthStatus(backend: .driverKit,
                                  kanataRunning: true,
                                  karabinerDaemonRunning: true,
                                  vhidHealthy: true)

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
            helper: HelperStatus(
                isInstalled: true,
                version: WizardHelperConstants.expectedHelperVersion,
                isWorking: true
            ),
            system: EngineSystemInfo(macOSVersion: "26.0.1", driverCompatible: true),
            timestamp: Date()
        )

        // Run adapt twice to mimic reopen/open flows
        let first = SystemStateResult.projecting(context)
        let second = SystemStateResult.projecting(context)

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
            timestamp: Date(), backend: .driverKit
        )

        let health = HealthStatus(backend: .driverKit,
                                  kanataRunning: true,
                                  karabinerDaemonRunning: true,
                                  vhidHealthy: true,
                                  kanataInputCaptureReady: false,
                                  kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureBuiltInKeyboardReason)

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
            helper: HelperStatus(
                isInstalled: true,
                version: WizardHelperConstants.expectedHelperVersion,
                isWorking: true
            ),
            system: EngineSystemInfo(macOSVersion: "26.0.1", driverCompatible: true),
            timestamp: Date()
        )

        let adapted = SystemStateResult.projecting(context)

        XCTAssertEqual(adapted.state, .missingPermissions(missing: [.kanataInputMonitoring]))
        XCTAssertTrue(
            adapted.issues.contains { issue in
                issue.identifier == .permission(.kanataInputMonitoring)
            }
        )
    }

    func testRunningSessionWithoutInputCaptureRoutesToRuntimeRepair() {
        let now = Date()
        let capabilities = PermissionOracle.PermissionSet(
            accessibility: .granted, inputMonitoring: .granted,
            source: "independent-session", confidence: .high, timestamp: now
        )
        let context = SystemContext(
            permissions: .init(keyPath: capabilities, kanata: capabilities, timestamp: now, backend: .session),
            services: HealthStatus(
                backend: .session, kanataProcessRunning: true, kanataTCPResponding: true,
                kanataRunning: true, karabinerDaemonRunning: false, vhidHealthy: false,
                kanataInputCaptureReady: false,
                kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureBuiltInKeyboardReason
            ),
            conflicts: .empty,
            components: ComponentStatus(
                kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true,
                karabinerDriverInstalled: false, karabinerDaemonRunning: false,
                vhidDeviceInstalled: false, vhidDeviceHealthy: false,
                vhidServicesHealthy: false, vhidVersionMismatch: false
            ), helper: .empty, system: EngineSystemInfo(macOSVersion: "27.0", driverCompatible: false),
            timestamp: now
        )
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(result.state, .serviceNotRunning)
        XCTAssertEqual(result.autoFixActions, [.restartCommServer])
        XCTAssertTrue(result.issues.contains { $0.identifier == .daemon })
        XCTAssertFalse(result.issues.contains { $0.category == .permissions })
    }
}
