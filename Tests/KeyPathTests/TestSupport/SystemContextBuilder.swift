import Foundation
import KeyPathAppKit
import KeyPathPermissions
import KeyPathWizardCore

/// Tiny helper to construct SystemContext for planner/engine tests without touching real system state.
struct SystemContextBuilder {
    var permissionsStatus: PermissionOracle.Status = .granted
    var helperReady: Bool = true
    var servicesHealthy: Bool = false
    var componentsInstalled: Bool = false
    var conflicts: [SystemConflict] = []

    func build() -> SystemContext {
        let permissionSet = PermissionOracle.PermissionSet(
            accessibility: permissionsStatus,
            inputMonitoring: permissionsStatus,
            source: "test",
            confidence: .high,
            timestamp: Date()
        )
        let permissions = PermissionOracle.Snapshot(
            keyPath: permissionSet,
            kanata: permissionSet,
            timestamp: Date()
        )

        let helper = HelperStatus(isInstalled: helperReady, version: "1.0", isWorking: helperReady)

        let components: ComponentStatus = if componentsInstalled {
            ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: servicesHealthy,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: servicesHealthy,
                launchDaemonServicesHealthy: servicesHealthy,
                vhidVersionMismatch: false
            )
        } else {
            .empty
        }

        let services = servicesHealthy
            ? HealthStatus(kanataRunning: true, karabinerDaemonRunning: true, vhidHealthy: true)
            : HealthStatus.empty

        let conflictStatus = ConflictStatus(conflicts: conflicts, canAutoResolve: !conflicts.isEmpty)

        return SystemContext(
            permissions: permissions,
            services: services,
            conflicts: conflictStatus,
            components: components,
            helper: helper,
            system: EngineSystemInfo(macOSVersion: "15.0", driverCompatible: true),
            timestamp: Date()
        )
    }

    static func cleanInstall() -> SystemContext {
        SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: false,
            servicesHealthy: false,
            componentsInstalled: false
        ).build()
    }

    static func degradedRepair() -> SystemContext {
        SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: true
        ).build()
    }
}
