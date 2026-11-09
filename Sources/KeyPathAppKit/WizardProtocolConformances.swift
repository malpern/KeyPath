import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - RuntimeCoordinator + RuntimeCoordinating

extension RuntimeCoordinator: RuntimeCoordinating {
    public func currentRuntimeStatus() async -> WizardRuntimeStatus {
        let status = await serviceLifecycleCoordinator.currentRuntimeStatus()
        switch status {
        case let .running(pid): return .running(pid: pid)
        case .stopped: return .stopped
        case let .failed(reason): return .failed(reason: reason)
        case .starting: return .starting
        case .unknown: return .unknown
        }
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

// MARK: - TCPProbe + WizardTCPProbing

extension TCPProbe: WizardTCPProbing {}

// MARK: - WizardDependencies Configuration

/// Configure WizardDependencies at app launch (call from App.init or similar)
@MainActor
public func configureWizardDependencies(runtimeCoordinator: RuntimeCoordinator) {
    WizardDependencies.isRunningAdHoc = WizardSignatureHealthCheck.isRunningAdHoc()
    WizardDependencies.runtimeCoordinator = runtimeCoordinator
    let sharedValidator = SystemValidator(kanataManager: runtimeCoordinator)
    WizardDependencies.systemValidator = sharedValidator

    // Share the same validator with MainAppStateController so there's only one instance app-wide.
    // This ensures inProgressValidation dedup spans all callers.
    MainAppStateController.shared.setValidator(sharedValidator)
    WizardDependencies.permissionRequestService = PermissionRequestService.shared

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
    WizardDependencies.resourceBundle = KeyPathAppKitResources.bundle

    // ExternalKanataService static methods
    WizardDependencies.getExternalKanataInfo = {
        ExternalKanataService.getExternalKanataInfo()
    }
    WizardDependencies.stopExternalKanata = { info in
        let result = await ExternalKanataService.stopExternalKanata(info)
        switch result {
        case .success: return .success(())
        case .processNotFound: return .success(())
        case let .killFailed(reason): return .failure(NSError(domain: "ExternalKanata", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
        case let .launchAgentDisableFailed(reason): return .failure(NSError(domain: "ExternalKanata", code: 2, userInfo: [NSLocalizedDescriptionKey: reason]))
        }
    }
    WizardDependencies.hasExternalKanataRunning = {
        ExternalKanataService.hasExternalKanataRunning()
    }

    // Page view factories for pages that live in KeyPathAppKit
    WizardDependencies.makeKanataMigrationPage = { onMigrationComplete, onSkip in
        AnyView(WizardKanataMigrationPage(
            onMigrationComplete: onMigrationComplete,
            onSkip: onSkip
        ))
    }
    WizardDependencies.makeKarabinerImportPage = { onImportComplete, onSkip in
        AnyView(WizardKarabinerImportPage(
            onImportComplete: onImportComplete,
            onSkip: onSkip
        ))
    }
}

/// Configure WizardDependencies for app-bundled CLI repair/inspect entry points.
@MainActor
func configureCLIWizardDependencies(systemValidator: SystemValidator) {
    WizardDependencies.runtimeCoordinator = nil
    WizardDependencies.systemValidator = systemValidator

    MainAppStateController.shared.setValidator(systemValidator)
    WizardDependencies.permissionRequestService = PermissionRequestService.shared

    // The CLI cannot uninstall: the session runtime belongs to the running app.
    WizardDependencies.createUninstallCoordinator = nil
    WizardDependencies.resourceBundle = KeyPathAppKitResources.bundle

    WizardDependencies.getExternalKanataInfo = {
        ExternalKanataService.getExternalKanataInfo()
    }
    WizardDependencies.stopExternalKanata = { info in
        let result = await ExternalKanataService.stopExternalKanata(info)
        switch result {
        case .success, .processNotFound:
            return .success(())
        case let .killFailed(reason):
            return .failure(NSError(
                domain: "ExternalKanata",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: reason]
            ))
        case let .launchAgentDisableFailed(reason):
            return .failure(NSError(
                domain: "ExternalKanata",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: reason]
            ))
        }
    }
    WizardDependencies.hasExternalKanataRunning = {
        ExternalKanataService.hasExternalKanataRunning()
    }
}
