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

extension SystemValidator: WizardSystemValidating {
    public func checkSystem() async -> SystemSnapshot {
        await checkSystem(progressCallback: { _ in })
    }

    public func checkSystem(freshness: WizardSystemSnapshotFreshness) async -> SystemSnapshot {
        await checkSystem(freshness: freshness, progressCallback: { _ in })
    }
}

// MARK: - PermissionRequestService + WizardPermissionRequesting

extension PermissionRequestService: WizardPermissionRequesting {}

// MARK: - WizardDependencies Configuration

/// Configure WizardDependencies at app launch (call from App.init or similar)
@MainActor
public func configureWizardDependencies(runtimeCoordinator: RuntimeCoordinator) {
    WizardDependencies.runtimeCoordinator = runtimeCoordinator
    let sharedValidator = SystemValidator(kanataManager: runtimeCoordinator)
    WizardDependencies.systemValidator = sharedValidator

    // Share the same validator with MainAppStateController so there's only one instance app-wide.
    // This ensures inProgressValidation dedup spans all callers.
    MainAppStateController.shared.setValidator(sharedValidator)

    WizardDependencies.createUninstallCoordinator = {
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
}

/// Configure WizardDependencies for app-bundled CLI repair/inspect entry points.
@MainActor
func configureCLIWizardDependencies(systemValidator: SystemValidator) {
    WizardDependencies.runtimeCoordinator = nil
    WizardDependencies.systemValidator = systemValidator

    MainAppStateController.shared.setValidator(systemValidator)

    // The CLI cannot uninstall: the session runtime belongs to the running app.
    WizardDependencies.createUninstallCoordinator = nil
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
