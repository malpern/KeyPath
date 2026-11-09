import Foundation
import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore

/// Tiny helper to construct SystemContext for planner/engine tests without touching real system state.
struct SystemContextBuilder {
    var snapshotID = UUID()
    var permissionsStatus: PermissionOracle.Status = .granted
    var servicesHealthy: Bool = false
    var kanataProcessRunning: Bool?
    var kanataTCPResponding: Bool?
    var kanataRunning: Bool?
    var kanataInputCaptureReady: Bool = true
    /// The input-capture failure reason surfaced when not ready (#624 attribution).
    /// Defaults to the built-in-keyboard permission reason; set to a grab-failure
    /// reason, or explicitly nil, to exercise the other branches.
    var kanataInputCaptureIssue: String? = "kanata-cannot-open-built-in-keyboard"
    var componentsInstalled: Bool = false
    var conflicts: [SystemConflict] = []
    var captureStatus: SystemSnapshotCaptureStatus = .complete

    func build() -> SystemContext {
        let permissions = PermissionOracle.Snapshot.fixture(
            accessibility: permissionsStatus, runtimeKeyAccess: permissionsStatus
        )

        let components: ComponentStatus = if componentsInstalled {
            ComponentStatus(kanataBinaryInstalled: true)
        } else {
            .empty
        }

        let services = HealthStatus(
            kanataProcessRunning: kanataProcessRunning,
            kanataTCPResponding: kanataTCPResponding,
            kanataRunning: kanataRunning ?? servicesHealthy,
            kanataInputCaptureReady: kanataInputCaptureReady,
            kanataInputCaptureIssue: kanataInputCaptureReady ? nil : kanataInputCaptureIssue
        )

        let conflictStatus = ConflictStatus(conflicts: conflicts, canAutoResolve: !conflicts.isEmpty)

        return SystemContext(
            snapshotID: snapshotID,
            permissions: permissions,
            services: services,
            conflicts: conflictStatus,
            components: components,
            system: EngineSystemInfo(macOSVersion: "27.0"),
            timestamp: Date(),
            captureStatus: captureStatus
        )
    }

    static func cleanInstall() -> SystemContext {
        SystemContextBuilder(
            permissionsStatus: .granted,
            servicesHealthy: false,
            componentsInstalled: false
        ).build()
    }

    static func degradedRepair() -> SystemContext {
        SystemContextBuilder(
            permissionsStatus: .granted,
            servicesHealthy: false,
            componentsInstalled: true
        ).build()
    }
}
