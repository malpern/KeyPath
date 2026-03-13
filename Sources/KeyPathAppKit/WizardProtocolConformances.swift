import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore

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

    /// Explicit protocol-satisfying overload for startKanata.
    /// The full method in RuntimeCoordinator+ServiceManagement has extra default params
    /// (precomputedDecision), so a single-label overload is needed to satisfy the protocol.
    @discardableResult
    public func startKanata(reason: String) async -> Bool {
        await serviceLifecycleCoordinator.startKanata(reason: reason, precomputedDecision: nil)
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
        let state = await refreshManagementStateInternal()
        switch state {
        case .legacyActive: return .legacyActive
        case .smappserviceActive: return .smappserviceActive
        case .smappservicePending: return .smappservicePending
        case .uninstalled: return .uninstalled
        case .conflicted: return .conflicted
        case .unknown: return .unknown
        }
    }

    public nonisolated var kanataServiceID: String {
        Self.kanataServiceID
    }

    public nonisolated var legacyPlistPath: String {
        Self.legacyPlistPath
    }

    public func preferredLaunchctlTargets(for state: WizardServiceManagementState) -> [String] {
        let internalState: ServiceManagementState
        switch state {
        case .legacyActive: internalState = .legacyActive
        case .smappserviceActive: internalState = .smappserviceActive
        case .smappservicePending: internalState = .smappservicePending
        case .uninstalled: internalState = .uninstalled
        case .conflicted: internalState = .conflicted
        case .unknown: internalState = .unknown
        }
        return Self.preferredLaunchctlTargets(for: internalState)
    }
}

// MARK: - SystemValidator + WizardSystemValidating

extension SystemValidator: WizardSystemValidating {
    public func checkSystem() async -> SystemSnapshot {
        await checkSystem(progressCallback: { _ in })
    }
}

// MARK: - KanataSplitRuntimeHostService + WizardSplitRuntimeHosting

extension KanataSplitRuntimeHostService: WizardSplitRuntimeHosting {}

// MARK: - HelperMaintenance + WizardHelperMaintaining

extension HelperMaintenance: WizardHelperMaintaining {}

// MARK: - FullDiskAccessChecker + WizardFullDiskAccessChecking

extension FullDiskAccessChecker: WizardFullDiskAccessChecking {}

// MARK: - PermissionRequestService + WizardPermissionRequesting

extension PermissionRequestService: WizardPermissionRequesting {}

// MARK: - PrivilegedOperationsCoordinator + WizardPrivilegedOperating

extension PrivilegedOperationsCoordinator: WizardPrivilegedOperating {}

// Note: ExternalKanataService cannot directly conform to WizardExternalKanataProviding
// because its stopExternalKanata returns StopResult, not Result<Void, Error>.
// The wizard accesses ExternalKanataService via WizardDependencies closures (see configureWizardDependencies).

// MARK: - TCPProbe + WizardTCPProbing

extension TCPProbe: WizardTCPProbing {}

// MARK: - KanataRuntimePathCoordinator + WizardRuntimePathCoordinating

/// Wrapper to provide an instance-based conformance for the static-only KanataRuntimePathCoordinator enum.
@MainActor
public final class KanataRuntimePathCoordinatorAdapter: WizardRuntimePathCoordinating {
    public init() {}

    public func evaluateCurrentPath() async -> KanataRuntimePathDecision? {
        await KanataRuntimePathCoordinator.evaluateCurrentPath()
    }
}

// MARK: - UninstallCoordinator + WizardUninstalling

extension UninstallCoordinator: WizardUninstalling {}

// MARK: - WizardDependencies Configuration

/// Configure WizardDependencies at app launch (call from App.init or similar)
@MainActor
public func configureWizardDependencies(runtimeCoordinator: RuntimeCoordinator) {
    WizardDependencies.runtimeCoordinator = runtimeCoordinator
    WizardDependencies.helperManager = HelperManager.shared
    WizardDependencies.daemonManager = KanataDaemonManager.shared
    WizardDependencies.systemValidator = SystemValidator(processLifecycleManager: runtimeCoordinator.processLifecycleManager)
    WizardDependencies.splitRuntimeHost = KanataSplitRuntimeHostService.shared
    WizardDependencies.helperMaintenance = HelperMaintenance.shared
    WizardDependencies.runtimePathCoordinator = KanataRuntimePathCoordinatorAdapter()
    WizardDependencies.fullDiskAccessChecker = FullDiskAccessChecker.shared
    WizardDependencies.permissionRequestService = PermissionRequestService.shared
    WizardDependencies.privilegedOperations = PrivilegedOperationsCoordinator.shared

    WizardDependencies.smServiceFactory = { plistName in
        HelperManager.smServiceFactory(plistName)
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
}
