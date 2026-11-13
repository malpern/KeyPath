import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - RuntimeCoordinator + RuntimeCoordinating

extension RuntimeCoordinator: RuntimeCoordinating {
    public func currentRuntimeStatus() async -> RuntimeStatus {
        await serviceLifecycleCoordinator.currentRuntimeStatus()
    }

    public func isInTransientRuntimeStartupWindow() async -> Bool {
        await serviceLifecycleCoordinator.isInTransientRuntimeStartupWindow()
    }
}

// MARK: - SystemValidator + WizardSystemValidating

extension SystemValidator: WizardSystemValidating {}

// MARK: - PermissionRequestService + WizardPermissionRequesting

extension PermissionRequestService: WizardPermissionRequesting {}

// MARK: - InstallerServices

/// Sets the installer's services at app launch.
@MainActor
public func configureInstallerServices(runtimeCoordinator: RuntimeCoordinator) {
    let sharedValidator = SystemValidator(kanataManager: runtimeCoordinator)
    // Both the main app and wizard use the same capture path.
    MainAppStateController.shared.setValidator(sharedValidator)

    InstallerServices.current = InstallerServices(
        systemValidator: sharedValidator,
        runtime: runtimeCoordinator,
        makeUninstaller: {
            SessionUninstallCoordinator(prepare: {
                runtimeCoordinator.serviceLifecycleCoordinator.setTerminationPreparationActive(true)
                guard await runtimeCoordinator.stopKanata(reason: "Uninstall KeyPath") else { return false }
                runtimeCoordinator.stopConfigFileWatching()
                await runtimeCoordinator.configurationService.operationGate.suspendForUninstall()
                return true
            }, resume: {
                await runtimeCoordinator.configurationService.operationGate.resumeAfterFailedUninstall()
                runtimeCoordinator.serviceLifecycleCoordinator.setTerminationPreparationActive(false)
                runtimeCoordinator.startConfigFileWatching()
            }, removeLoginItem: {
                try await LaunchAtLoginController.shared.setEnabled(false)
            }, stopSessionWorkers: {
                let outcome = await SessionWorkerSweep.live(uninstalling: Bundle.main.bundleURL).stopAll()
                AppLogger.shared.log(
                    "[Uninstall] Session worker sweep verified=\(outcome.verified) found=\(outcome.found.map(\.pid)) remaining=\(outcome.remaining.map(\.pid))"
                )
                return outcome.result
            })
        }
    )
}

/// Sets the installer's services for the app-bundled CLI's repair and inspect commands.
/// The CLI has no runtime of its own and cannot uninstall: both belong to the running app.
@MainActor
func configureCLIInstallerServices(systemValidator: SystemValidator) {
    MainAppStateController.shared.setValidator(systemValidator)
    InstallerServices.current = InstallerServices(systemValidator: systemValidator)
}

public extension WizardHost {
    /// The app's pages and services for the wizard. Wizard hosts set this in
    /// the SwiftUI environment.
    @MainActor
    static var app: WizardHost {
        WizardHost(
            makeKanataMigrationPage: { onMigrationComplete, onSkip in
                AnyView(WizardKanataMigrationPage(onMigrationComplete: onMigrationComplete, onSkip: onSkip))
            },
            makeKarabinerImportPage: { onImportComplete, onSkip in
                AnyView(WizardKarabinerImportPage(onImportComplete: onImportComplete, onSkip: onSkip))
            },
            externalKanata: ExternalKanataOperations(
                info: { ExternalKanataService.getExternalKanataInfo() },
                stop: { info in
                    switch await ExternalKanataService.stopExternalKanata(info) {
                    case .success, .processNotFound:
                        .success(())
                    case let .killFailed(reason):
                        .failure(NSError(domain: "ExternalKanata", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
                    case let .launchAgentDisableFailed(reason):
                        .failure(NSError(domain: "ExternalKanata", code: 2, userInfo: [NSLocalizedDescriptionKey: reason]))
                    }
                },
                isRunning: { ExternalKanataService.hasExternalKanataRunning() }
            ),
            permissionRequests: PermissionRequestService.shared
        )
    }
}
