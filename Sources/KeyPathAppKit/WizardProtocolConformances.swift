import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - WizardServiceManagementState ↔ KanataDaemonManager.ServiceManagementState converters

extension WizardServiceManagementState {
    /// Convert from the internal ServiceManagementState type (defined in KeyPathAppKit).
    init(_ state: KanataDaemonManager.ServiceManagementState) {
        // EXHAUSTIVE: must mirror KanataDaemonManager.ServiceManagementState exactly — do not add a default case
        switch state {
        case .legacyActive: self = .legacyActive
        case .smappserviceActive: self = .smappserviceActive
        case .smappservicePending: self = .smappservicePending
        case .uninstalled: self = .uninstalled
        case .conflicted: self = .conflicted
        case .unknown: self = .unknown
        }
    }

    /// Convert back to the internal ServiceManagementState type.
    var asInternal: KanataDaemonManager.ServiceManagementState {
        // EXHAUSTIVE: must mirror KanataDaemonManager.ServiceManagementState exactly — do not add a default case
        switch self {
        case .legacyActive: return .legacyActive
        case .smappserviceActive: return .smappserviceActive
        case .smappservicePending: return .smappservicePending
        case .uninstalled: return .uninstalled
        case .conflicted: return .conflicted
        case .unknown: return .unknown
        }
    }
}

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

    public func runFullRepair(reason: String) async -> WizardRepairReport {
        let report = await installerEngine.run(intent: .repair, using: privilegeBroker)
        return WizardRepairReport(
            success: report.success,
            successCount: report.executedRecipes.filter(\.success).count,
            totalCount: report.executedRecipes.count,
            failureReason: report.failureReason
        )
    }
}

// MARK: - HelperManager + WizardHelperManaging

extension HelperManager: WizardHelperManaging {}

// MARK: - KanataDaemonManager + WizardDaemonManaging

extension KanataDaemonManager: WizardDaemonManaging {
    public func refreshManagementState() async -> WizardServiceManagementState {
        WizardServiceManagementState(await refreshManagementStateInternal())
    }

    public nonisolated var kanataServiceID: String {
        Self.kanataServiceID
    }

    public nonisolated var legacyPlistPath: String {
        Self.legacyPlistPath
    }

    public func preferredLaunchctlTargets(for state: WizardServiceManagementState) -> [String] {
        Self.preferredLaunchctlTargets(for: state.asInternal)
    }
}

// MARK: - SystemValidator + WizardSystemValidating

extension SystemValidator: WizardSystemValidating {
    public func checkSystem() async -> SystemSnapshot {
        await checkSystem(progressCallback: { _ in })
    }
}

// MARK: - HelperMaintenance + WizardHelperMaintaining

extension HelperMaintenance: WizardHelperMaintaining {}

// MARK: - FullDiskAccessChecker + WizardFullDiskAccessChecking

extension FullDiskAccessChecker: WizardFullDiskAccessChecking {}

// MARK: - PermissionRequestService + WizardPermissionRequesting

extension PermissionRequestService: WizardPermissionRequesting {}

// MARK: - PrivilegedOperationsRouter + WizardPrivilegedOperating

extension PrivilegedOperationsRouter: WizardPrivilegedOperating {}

// MARK: - TCPProbe + WizardTCPProbing

extension TCPProbe: WizardTCPProbing {}

// MARK: - UninstallCoordinator + WizardUninstalling

extension UninstallCoordinator: WizardUninstalling {}

// MARK: - WizardDependencies Configuration

/// Configure WizardDependencies at app launch (call from App.init or similar)
@MainActor
public func configureWizardDependencies(runtimeCoordinator: RuntimeCoordinator) {
    WizardDependencies.isRunningAdHoc = WizardSignatureHealthCheck.isRunningAdHoc()
    WizardDependencies.runtimeCoordinator = runtimeCoordinator
    WizardDependencies.helperManager = HelperManager.shared
    WizardDependencies.daemonManager = KanataDaemonManager.shared
    let sharedValidator = SystemValidator(
        processLifecycleManager: runtimeCoordinator.processLifecycleManager,
        kanataManager: runtimeCoordinator
    )
    WizardDependencies.systemValidator = sharedValidator

    // Share the same validator with MainAppStateController so there's only one instance app-wide.
    // This ensures inProgressValidation dedup spans all callers.
    MainAppStateController.shared.setValidator(sharedValidator)
    WizardDependencies.helperMaintenance = HelperMaintenance.shared
    WizardDependencies.fullDiskAccessChecker = FullDiskAccessChecker.shared
    WizardDependencies.permissionRequestService = PermissionRequestService.shared
    WizardDependencies.privilegedOperations = PrivilegedOperationsRouter.shared

    WizardDependencies.smServiceFactory = { plistName in
        HelperManager.smServiceFactory(plistName)
    }
    WizardDependencies.helperNeedsApproval = {
        HelperManager.smServiceFactory(HelperManager.helperPlistName).status == .requiresApproval
    }
    WizardDependencies.createUninstallCoordinator = {
        UninstallCoordinator()
    }
    WizardDependencies.executePrivilegedBatch = { batch in
        let result = try await AdminCommandExecutorHolder.shared.execute(batch: batch)
        return (exitCode: result.exitCode, output: result.output)
    }
    WizardDependencies.resourceBundle = Bundle.module

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

    // TCPProbe
    WizardDependencies.tcpProbe = { port, timeoutMs in
        TCPProbe.probe(port: port, timeoutMs: timeoutMs)
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
    WizardDependencies.makeCommunicationPage = { onAutoFix in
        AnyView(WizardCommunicationPage(
            onAutoFix: onAutoFix
        ))
    }
}
