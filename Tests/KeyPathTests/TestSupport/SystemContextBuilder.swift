import Foundation
import KeyPathAppKit
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore

/// Tiny helper to construct SystemContext for planner/engine tests without touching real system state.
struct SystemContextBuilder {
    var snapshotID = UUID()
    var permissionsStatus: PermissionOracle.Status = .granted
    var helperReady: Bool = true
    var helperRequiresApproval: Bool = false
    var servicesHealthy: Bool = false
    var kanataLaunchdLoaded: Bool?
    var kanataProcessRunning: Bool?
    var kanataTCPResponding: Bool?
    var kanataTCPConfigured: Bool?
    var kanataSMAppServiceRegistered: Bool?
    var kanataRunning: Bool?
    var karabinerDaemonRunning: Bool?
    var vhidHealthy: Bool?
    var loginItemsApprovalRequired: Bool?
    var kanataInputCaptureReady: Bool = true
    /// The input-capture failure reason surfaced when not ready (#624 attribution).
    /// Defaults to the built-in-keyboard permission reason; set to a grab-failure
    /// reason, or explicitly nil, to exercise the other branches.
    var kanataInputCaptureIssue: String? = ServiceHealthChecker.inputCaptureBuiltInKeyboardReason
    var componentsInstalled: Bool = false
    var conflicts: [SystemConflict] = []
    var driverCompatible: Bool = true
    var captureStatus: SystemSnapshotCaptureStatus = .complete

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

        let helper = HelperStatus(
            isInstalled: helperReady || helperRequiresApproval,
            version: WizardHelperConstants.expectedHelperVersion,
            isWorking: helperReady,
            requiresApproval: helperRequiresApproval
        )

        let components: ComponentStatus = if componentsInstalled {
            ComponentStatus(
                kanataBinaryInstalled: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: servicesHealthy,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: servicesHealthy,
                vhidServicesHealthy: servicesHealthy,
                vhidVersionMismatch: false
            )
        } else {
            .empty
        }

        let services = HealthStatus(
            kanataLaunchdLoaded: kanataLaunchdLoaded,
            kanataProcessRunning: kanataProcessRunning,
            kanataTCPResponding: kanataTCPResponding,
            kanataTCPConfigured: kanataTCPConfigured,
            kanataRunning: kanataRunning ?? servicesHealthy,
            karabinerDaemonRunning: karabinerDaemonRunning ?? servicesHealthy,
            vhidHealthy: vhidHealthy ?? servicesHealthy,
            kanataInputCaptureReady: kanataInputCaptureReady,
            kanataInputCaptureIssue: kanataInputCaptureReady ? nil : kanataInputCaptureIssue,
            kanataSMAppServiceRegistered: kanataSMAppServiceRegistered,
            loginItemsApprovalRequired: loginItemsApprovalRequired
        )

        let conflictStatus = ConflictStatus(conflicts: conflicts, canAutoResolve: !conflicts.isEmpty)

        return SystemContext(
            snapshotID: snapshotID,
            permissions: permissions,
            services: services,
            conflicts: conflictStatus,
            components: components,
            helper: helper,
            system: EngineSystemInfo(macOSVersion: "15.0", driverCompatible: driverCompatible),
            timestamp: Date(),
            captureStatus: captureStatus
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
