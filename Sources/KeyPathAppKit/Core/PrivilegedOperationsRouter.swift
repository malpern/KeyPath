import AppKit
import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathWizardCore

@MainActor
protocol PrivilegedOperationsCoordinating: WizardPrivilegedOperating {}

/// Routes privileged operations through the XPC helper, with direct sudo fallback for tests.
/// Slim replacement for PrivilegedOperationsCoordinator — pure routing, no domain logic.
@MainActor
public final class PrivilegedOperationsRouter {
    private let helperManager: HelperManager
    private let subprocessRunner: SubprocessRunner
    private let kanataDaemonManager: KanataDaemonManager
    private let serviceHealthChecker: ServiceHealthChecker

    static let shared = PrivilegedOperationsRouter()

    private static var lastServiceInstallAttempt: Date?
    private static var lastSMAppApprovalNotice: Date?
    private static let smAppApprovalNoticeThrottle: TimeInterval = KeyPathConstants.Timing.smAppApprovalThrottle

    private static let kanataReadinessTimeout: TimeInterval = KeyPathConstants.Timing.kanataReadinessTimeout
    private static let kanataReadinessPollIntervalSeconds: TimeInterval = KeyPathConstants.Timing.kanataReadinessPollInterval
    private static let kanataLaunchctlNotFoundExitCode: Int32 = 113
    private static let persistentLaunchctlNotFoundThreshold = 3

    private static let vhidVerifyTimeoutSeconds: Double = 1.5
    private static let postconditionPollInterval: Duration = .milliseconds(100)
    private static let vhidSettleDelay: Duration = .milliseconds(150)
    private static let processTerminationVerifyTimeoutSeconds: Double = 1.0
    private static let kanataStopVerifyTimeoutSeconds: Double = 1.0

    #if DEBUG
        nonisolated(unsafe) static var operationModeOverride: OperationMode?
        nonisolated(unsafe) static var serviceStateOverride:
            (() -> KanataDaemonManager.ServiceManagementState)?
        nonisolated(unsafe) static var installAllServicesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var recoverRequiredRuntimeServicesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var killExistingKanataProcessesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var helperRecoverRequiredRuntimeServicesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var sudoRestartServicesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var helperInstallNewsyslogConfigOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var sudoInstallNewsyslogConfigOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var helperInstallCorrectVHIDDriverOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var sudoInstallCorrectVHIDDriverOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var bundledVHIDDriverPackagePathOverride: (() -> String?)?
        nonisolated(unsafe) static var helperTerminateProcessOverride: ((Int32) async throws -> Void)?
        nonisolated(unsafe) static var sudoTerminateProcessOverride: ((Int32) async throws -> Void)?
        nonisolated(unsafe) static var helperKillAllKanataOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var sudoKillAllKanataOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var activateVirtualHIDManagerOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var downloadAndInstallCorrectVHIDDriverOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var kanataReadinessOverride:
            ((String) async -> KanataReadinessResult)?
        nonisolated(unsafe) static var helperRepairVHIDDaemonServicesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var sudoRepairVHIDServicesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var vhidServicesPostconditionOverride: ((String) async -> Bool)?
        nonisolated(unsafe) static var vhidDriverPostconditionOverride: ((String) async -> Bool)?
        nonisolated(unsafe) static var processTerminatedPostconditionOverride: ((Int32, String) async -> Bool)?
        nonisolated(unsafe) static var kanataStoppedPostconditionOverride: ((String) async -> Bool)?
        nonisolated(unsafe) static var newsyslogPostconditionOverride: (() -> Bool)?

        static func resetTestingState() {
            operationModeOverride = nil
            serviceStateOverride = nil
            installAllServicesOverride = nil
            recoverRequiredRuntimeServicesOverride = nil
            killExistingKanataProcessesOverride = nil
            helperRecoverRequiredRuntimeServicesOverride = nil
            sudoRestartServicesOverride = nil
            helperInstallNewsyslogConfigOverride = nil
            sudoInstallNewsyslogConfigOverride = nil
            helperInstallCorrectVHIDDriverOverride = nil
            sudoInstallCorrectVHIDDriverOverride = nil
            bundledVHIDDriverPackagePathOverride = nil
            helperTerminateProcessOverride = nil
            sudoTerminateProcessOverride = nil
            helperKillAllKanataOverride = nil
            sudoKillAllKanataOverride = nil
            activateVirtualHIDManagerOverride = nil
            downloadAndInstallCorrectVHIDDriverOverride = nil
            kanataReadinessOverride = nil
            helperRepairVHIDDaemonServicesOverride = nil
            sudoRepairVHIDServicesOverride = nil
            vhidServicesPostconditionOverride = nil
            vhidDriverPostconditionOverride = nil
            processTerminatedPostconditionOverride = nil
            kanataStoppedPostconditionOverride = nil
            newsyslogPostconditionOverride = nil
            lastServiceInstallAttempt = nil
            lastSMAppApprovalNotice = nil
            ServiceInstallGuard.reset()
            KanataDaemonManager.registeredButNotLoadedOverride = nil
            ServiceHealthChecker.runtimeSnapshotOverride = nil
            ServiceHealthChecker.vhidDriverExtensionEnabledOverride = nil
            ServiceHealthChecker.vhidDriverExtensionStatusOverride = nil
        }
    #endif

    enum OperationMode {
        case privilegedHelper
        case directSudo
    }

    static var operationMode: OperationMode {
        #if DEBUG
            if let override = operationModeOverride {
                return override
            }
        #endif
        if TestEnvironment.isTestMode {
            return .directSudo
        }
        return .privilegedHelper
    }

    init(
        helperManager: HelperManager = .shared,
        subprocessRunner: SubprocessRunner = .shared,
        kanataDaemonManager: KanataDaemonManager = .shared,
        serviceHealthChecker: ServiceHealthChecker = .shared
    ) {
        self.helperManager = helperManager
        self.subprocessRunner = subprocessRunner
        self.kanataDaemonManager = kanataDaemonManager
        self.serviceHealthChecker = serviceHealthChecker
    }

    // MARK: - Operation Routing (helper-first with sudo fallback)

    public func cleanupPrivilegedHelper() async throws {
        let cmd = """
        /bin/launchctl bootout system/com.keypath.helper || true; \
        /bin/rm -f /Library/LaunchDaemons/com.keypath.helper.plist || true; \
        /bin/rm -f /Library/PrivilegedHelperTools/com.keypath.helper || true; \
        /bin/rm -f /var/log/com.keypath.helper.stdout.log /var/log/com.keypath.helper.stderr.log || true
        """
        try await sudoExecuteCommand(cmd, description: "Cleanup privileged helper")
    }

    public func installRequiredRuntimeServices() async throws {
        // Kanata is registered by KeyPath.app through SMAppService. Do not ask
        // the privileged helper to copy/bootstrap the app-bundled BundleProgram
        // plist as a legacy LaunchDaemon; launchd rejects that path and BTM state
        // becomes noisy. ServiceBootstrapper still uses privileged repair for
        // VHID services, then registers Kanata with SMAppService in-process.
        try await sudoInstallRequiredRuntimeServices()
        try await enforceVHIDServicesPostcondition(after: "installRequiredRuntimeServices")
        try await enforceKanataRuntimePostcondition(after: "installRequiredRuntimeServices")
    }

    public func recoverRequiredRuntimeServices() async throws {
        #if DEBUG
            if let override = Self.recoverRequiredRuntimeServicesOverride {
                try await override()
                return
            }
        #endif

        if try await installServicesIfUninstalled(context: "pre-restart") {
            try await enforceKanataRuntimePostcondition(after: "recoverRequiredRuntimeServices(pre-restart)")
            return
        }

        try await killExistingKanataProcessesForServiceRecovery()

        switch Self.operationMode {
        case .privilegedHelper:
            do {
                try await helperRecoverRequiredRuntimeServices()
                try await enforceKanataRuntimePostcondition(after: "recoverRequiredRuntimeServices(helper)")
            } catch {
                try await resolveHelperFailure(
                    operation: "recoverRequiredRuntimeServices",
                    error: error,
                    postcondition: { [self] in
                        await verifyKanataReadinessAfterInstall(
                            context: "recoverRequiredRuntimeServices(helper-error)"
                        ).isSuccess
                    },
                    fallback: { [self] in try await sudoRestartServices() },
                    enforcePostcondition: { [self] in
                        try await enforceKanataRuntimePostcondition(
                            after: "recoverRequiredRuntimeServices(sudo-fallback)"
                        )
                    }
                )
            }
        case .directSudo:
            try await sudoRestartServices()
        }

        if try await installServicesIfUninstalled(context: "post-restart") {
            // installed after restart
        }

        try await enforceKanataRuntimePostcondition(after: "recoverRequiredRuntimeServices")
    }

    @discardableResult
    public func installServicesIfUninstalled(context: String) async throws -> Bool {
        let state = await currentServiceState()

        let staleEnabledRegistration: Bool = if state == .smappserviceActive {
            await kanataDaemonManager.isRegisteredButNotLoaded()
        } else {
            false
        }

        let decision = ServiceInstallGuard.decide(
            state: state,
            staleEnabledRegistration: staleEnabledRegistration,
            now: Date(),
            lastAttempt: Self.lastServiceInstallAttempt
        )

        switch decision {
        case .skipPendingApproval:
            Self.notifySMAppServiceApprovalRequired(context: context)
            return false
        case .skipNoInstall:
            return false
        case .throttled:
            return false
        case .run:
            break
        }

        if state.needsMigration() {
            await removeLegacyKanataPlist(reason: context)
        }

        Self.lastServiceInstallAttempt = Date()
        try await runServiceInstall()
        return true
    }

    public func regenerateServiceConfiguration() async throws {
        try await sudoRegenerateConfig()
        try await enforceKanataRuntimePostcondition(after: "regenerateServiceConfiguration")
    }

    public func installNewsyslogConfig() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            do {
                try await helperInstallNewsyslogConfig()
                try enforceNewsyslogPostcondition(after: "installNewsyslogConfig(helper)")
            } catch {
                try await resolveHelperFailure(
                    operation: "installNewsyslogConfig",
                    error: error,
                    postcondition: { [self] in verifyNewsyslogPostcondition() },
                    fallback: { [self] in try await sudoInstallNewsyslogConfig() },
                    enforcePostcondition: { [self] in
                        try enforceNewsyslogPostcondition(after: "installNewsyslogConfig(sudo-fallback)")
                    }
                )
            }
        case .directSudo:
            try await sudoInstallNewsyslogConfig()
            try enforceNewsyslogPostcondition(after: "installNewsyslogConfig(sudo)")
        }
    }

    public func repairVHIDDaemonServices() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            do {
                try await helperRepairVHIDDaemonServices()
                try await enforceVHIDServicesPostcondition(after: "repairVHIDDaemonServices(helper)")
            } catch {
                try await resolveHelperFailure(
                    operation: "repairVHIDDaemonServices",
                    error: error,
                    postcondition: { [self] in
                        await verifyVHIDServicesPostcondition(
                            context: "repairVHIDDaemonServices(helper-error)"
                        )
                    },
                    fallback: { [self] in try await sudoRepairVHIDServices() },
                    enforcePostcondition: { [self] in
                        try await enforceVHIDServicesPostcondition(
                            after: "repairVHIDDaemonServices(sudo-fallback)"
                        )
                    }
                )
            }
        case .directSudo:
            try await sudoRepairVHIDServices()
            try await enforceVHIDServicesPostcondition(after: "repairVHIDDaemonServices(sudo)")
        }
    }

    public func activateVirtualHIDManager() async throws {
        #if DEBUG
            if let override = Self.activateVirtualHIDManagerOverride {
                try await override()
            } else {
                try await runActivateVirtualHIDManager()
            }
        #else
            try await runActivateVirtualHIDManager()
        #endif
        try await enforceVHIDServicesPostcondition(after: "activateVirtualHIDManager")
    }

    private func runActivateVirtualHIDManager() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            try await helperManager.activateVirtualHIDManager()
        case .directSudo:
            try await sudoActivateVHID()
        }
    }

    public func uninstallVirtualHIDDrivers() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            try await helperManager.uninstallVirtualHIDDrivers()
        case .directSudo:
            try await sudoUninstallDrivers()
        }
    }

    public func downloadAndInstallCorrectVHIDDriver() async throws {
        #if DEBUG
            if let override = Self.downloadAndInstallCorrectVHIDDriverOverride {
                try await override()
                try await enforceVHIDDriverPostcondition(after: "downloadAndInstallCorrectVHIDDriver")
                return
            }
        #endif

        switch Self.operationMode {
        case .privilegedHelper:
            do {
                #if DEBUG
                    let bundledPkgPath = Self.bundledVHIDDriverPackagePathOverride?()
                        ?? (WizardSystemPaths.bundledVHIDDriverPkgExists
                            ? WizardSystemPaths.bundledVHIDDriverPkgPath
                            : nil)
                #else
                    let bundledPkgPath = WizardSystemPaths.bundledVHIDDriverPkgExists
                        ? WizardSystemPaths.bundledVHIDDriverPkgPath
                        : nil
                #endif
                guard let bundledPkgPath else {
                    throw PrivilegedOperationError.operationFailed(
                        "Bundled VHID driver package not found."
                    )
                }
                try await helperInstallCorrectVHIDDriver(pkgPath: bundledPkgPath)
                try await enforceVHIDDriverPostcondition(after: "downloadAndInstallCorrectVHIDDriver(helper)")
            } catch {
                try await resolveHelperFailure(
                    operation: "downloadAndInstallCorrectVHIDDriver",
                    error: error,
                    postcondition: { [self] in
                        await verifyVHIDDriverPostcondition(
                            context: "downloadAndInstallCorrectVHIDDriver(helper-error)"
                        )
                    },
                    fallback: { [self] in try await sudoInstallCorrectDriver() },
                    enforcePostcondition: { [self] in
                        try await enforceVHIDDriverPostcondition(
                            after: "downloadAndInstallCorrectVHIDDriver(sudo-fallback)"
                        )
                    }
                )
            }
        case .directSudo:
            try await sudoInstallCorrectDriver()
            try await enforceVHIDDriverPostcondition(after: "downloadAndInstallCorrectVHIDDriver(sudo)")
        }
    }

    public func terminateProcess(pid: Int32) async throws {
        guard pid > 0 else {
            if !TestEnvironment.isTestMode {
                assertionFailure("[PrivOpsRouter] Invalid PID: \(pid)")
            }
            throw PrivilegedOperationError.operationFailed("Invalid process ID: \(pid)")
        }

        switch Self.operationMode {
        case .privilegedHelper:
            do {
                try await helperTerminateProcess(pid: pid)
                try await enforceProcessTerminatedPostcondition(pid: pid, after: "terminateProcess(helper)")
            } catch {
                try await resolveHelperFailure(
                    operation: "terminateProcess",
                    error: error,
                    postcondition: { [self] in
                        await verifyProcessTerminatedPostcondition(
                            pid: pid,
                            context: "terminateProcess(helper-error)"
                        )
                    },
                    fallback: { [self] in try await sudoTerminateProcess(pid: pid) },
                    enforcePostcondition: { [self] in
                        try await enforceProcessTerminatedPostcondition(
                            pid: pid,
                            after: "terminateProcess(sudo-fallback)"
                        )
                    }
                )
            }
        case .directSudo:
            try await sudoTerminateProcess(pid: pid)
            try await enforceProcessTerminatedPostcondition(pid: pid, after: "terminateProcess(sudo)")
        }
    }

    public func killAllKanataProcesses() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            do {
                try await helperKillAllKanataProcesses()
                try await enforceKanataStoppedPostcondition(after: "killAllKanataProcesses(helper)")
            } catch {
                try await resolveHelperFailure(
                    operation: "killAllKanataProcesses",
                    error: error,
                    postcondition: { [self] in
                        await verifyKanataStoppedPostcondition(
                            context: "killAllKanataProcesses(helper-error)"
                        )
                    },
                    fallback: { [self] in try await sudoKillAllKanata() },
                    enforcePostcondition: { [self] in
                        try await enforceKanataStoppedPostcondition(
                            after: "killAllKanataProcesses(sudo-fallback)"
                        )
                    }
                )
            }
        case .directSudo:
            try await sudoKillAllKanata()
            try await enforceKanataStoppedPostcondition(after: "killAllKanataProcesses(sudo)")
        }
    }

    public func restartKarabinerDaemonVerified() async throws -> Bool {
        switch Self.operationMode {
        case .privilegedHelper:
            try await helperRestartKarabinerDaemonVerified()
        case .directSudo:
            try await sudoRestartKarabinerDaemonVerified()
        }
    }

    public func disableKarabinerGrabber() async throws {
        try await helperManager.disableKarabinerGrabber()
    }

    public func sudoExecuteCommand(_ command: String, description: String) async throws {
        let result = try await AdminCommandExecutorHolder.shared.execute(
            command: command, description: description
        )
        if result.exitCode != 0 {
            throw PrivilegedOperationError.commandFailed(
                description: description,
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    // MARK: - Sudo Implementations

    private func sudoInstallRequiredRuntimeServices() async throws {
        #if DEBUG
            if let override = Self.installAllServicesOverride {
                try await override()
                return
            }
        #endif
        let success = await ServiceBootstrapper.shared.installAllServices()
        if !success {
            throw PrivilegedOperationError.installationFailed("Required runtime service installation failed")
        }
    }

    private func sudoRestartServices() async throws {
        #if DEBUG
            if let override = Self.sudoRestartServicesOverride {
                try await override()
                return
            }
        #endif
        let success = await ServiceBootstrapper.shared.recoverRequiredRuntimeServices()
        if !success {
            throw PrivilegedOperationError.operationFailed("Service restart failed")
        }
    }

    private func sudoRegenerateConfig() async throws {
        let success = await ServiceBootstrapper.shared.installAllServices()
        if !success {
            throw PrivilegedOperationError.operationFailed("Service regeneration failed")
        }
    }

    private func sudoInstallNewsyslogConfig() async throws {
        #if DEBUG
            if let override = Self.sudoInstallNewsyslogConfigOverride {
                try await override()
                return
            }
        #endif
        let success = await ServiceBootstrapper.shared.installNewsyslogConfig()
        if !success {
            throw PrivilegedOperationError.operationFailed("Newsyslog config installation failed")
        }
    }

    private func sudoRepairVHIDServices() async throws {
        #if DEBUG
            if let override = Self.sudoRepairVHIDServicesOverride {
                try await override()
                return
            }
        #endif
        let success = await ServiceBootstrapper.shared.repairVHIDDaemonServices()
        if !success {
            throw PrivilegedOperationError.operationFailed("VHID daemon repair failed")
        }
    }

    private func sudoActivateVHID() async throws {
        let vhidManager = VHIDDeviceManager()
        if await !(vhidManager.activateManager()) {
            throw PrivilegedOperationError.operationFailed("VirtualHID activation failed")
        }
    }

    private func sudoUninstallDrivers() async throws {
        let vhidManager = VHIDDeviceManager()
        if await !(vhidManager.uninstallAllDriverVersions()) {
            throw PrivilegedOperationError.operationFailed("Driver uninstallation failed")
        }
    }

    private func sudoInstallCorrectDriver() async throws {
        #if DEBUG
            if let override = Self.sudoInstallCorrectVHIDDriverOverride {
                try await override()
                return
            }
        #endif
        let vhidManager = VHIDDeviceManager()
        if await !(vhidManager.downloadAndInstallCorrectVersion()) {
            throw PrivilegedOperationError.operationFailed("Driver installation failed")
        }
    }

    private func sudoTerminateProcess(pid: Int32) async throws {
        #if DEBUG
            if let override = Self.sudoTerminateProcessOverride {
                try await override(pid)
                return
            }
        #endif
        do {
            try await sudoExecuteCommand("/bin/kill -TERM \(pid)", description: "Terminate process \(pid)")
        } catch {
            try await sudoExecuteCommand("/bin/kill -9 \(pid)", description: "Force kill process \(pid)")
        }
    }

    private func sudoKillAllKanata() async throws {
        #if DEBUG
            if let override = Self.sudoKillAllKanataOverride {
                try await override()
                return
            }
        #endif
        try await sudoExecuteCommand("/usr/bin/pkill -f kanata", description: "Kill all Kanata processes")
    }

    private func sudoExecuteBatch(_ batch: PrivilegedCommandRunner.Batch) async throws {
        let result = try await AdminCommandExecutorHolder.shared.execute(batch: batch)
        if result.exitCode != 0 {
            throw PrivilegedOperationError.commandFailed(
                description: batch.label,
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    // MARK: - Internal Helpers

    private func currentServiceState() async -> KanataDaemonManager.ServiceManagementState {
        #if DEBUG
            if let override = Self.serviceStateOverride {
                return override()
            }
        #endif
        return await kanataDaemonManager.refreshManagementStateInternal()
    }

    private func runServiceInstall() async throws {
        #if DEBUG
            if let override = Self.installAllServicesOverride {
                try await override()
                return
            }
        #endif
        try await installRequiredRuntimeServices()
    }

    private func helperRepairVHIDDaemonServices() async throws {
        #if DEBUG
            if let override = Self.helperRepairVHIDDaemonServicesOverride {
                try await override()
                return
            }
        #endif
        try await helperManager.repairVHIDDaemonServices()
    }

    private func helperRecoverRequiredRuntimeServices() async throws {
        #if DEBUG
            if let override = Self.helperRecoverRequiredRuntimeServicesOverride {
                try await override()
                return
            }
        #endif
        try await helperManager.recoverRequiredRuntimeServices()
    }

    private func helperInstallNewsyslogConfig() async throws {
        #if DEBUG
            if let override = Self.helperInstallNewsyslogConfigOverride {
                try await override()
                return
            }
        #endif
        try await helperManager.installNewsyslogConfig()
    }

    private func helperInstallCorrectVHIDDriver(pkgPath: String) async throws {
        #if DEBUG
            if let override = Self.helperInstallCorrectVHIDDriverOverride {
                try await override()
                return
            }
        #endif
        try await helperManager.installBundledVHIDDriver(pkgPath: pkgPath)
    }

    private func helperTerminateProcess(pid: Int32) async throws {
        #if DEBUG
            if let override = Self.helperTerminateProcessOverride {
                try await override(pid)
                return
            }
        #endif
        try await helperManager.terminateProcess(pid)
    }

    private func helperKillAllKanataProcesses() async throws {
        #if DEBUG
            if let override = Self.helperKillAllKanataOverride {
                try await override()
                return
            }
        #endif
        try await helperManager.killAllKanataProcesses()
    }

    private func killExistingKanataProcessesForServiceRecovery() async throws {
        #if DEBUG
            if let override = Self.killExistingKanataProcessesOverride {
                try await override()
                return
            }
        #endif

        switch Self.operationMode {
        case .privilegedHelper:
            do {
                try await helperKillAllKanataProcesses()
                try await enforceKanataStoppedPostcondition(
                    after: "killExistingKanataProcessesForServiceRecovery(helper)"
                )
            } catch {
                try await resolveHelperFailure(
                    operation: "killExistingKanataProcessesForServiceRecovery",
                    error: error,
                    postcondition: { [self] in
                        await verifyKanataStoppedPostcondition(
                            context: "killExistingKanataProcessesForServiceRecovery(helper-error)"
                        )
                    },
                    fallback: { [self] in try await sudoKillAllKanata() },
                    enforcePostcondition: { [self] in
                        try await enforceKanataStoppedPostcondition(
                            after: "killExistingKanataProcessesForServiceRecovery(sudo-fallback)"
                        )
                    }
                )
            }
        case .directSudo:
            try await sudoKillAllKanata()
            try await enforceKanataStoppedPostcondition(
                after: "killExistingKanataProcessesForServiceRecovery(sudo)"
            )
        }
    }

    private func resolveHelperFailure(
        operation: String,
        error: Error,
        postcondition: () async -> Bool,
        fallback: () async throws -> Void,
        enforcePostcondition: () async throws -> Void
    ) async throws {
        if await postcondition() {
            AppLogger.shared.log(
                "✅ [Router] \(operation) helper reply failed, but its postcondition is satisfied; skipping administrator fallback"
            )
            return
        }

        if case .ambiguousOutcome = error as? HelperManagerError {
            AppLogger.shared.log(
                "⚠️ [Router] \(operation) helper outcome is ambiguous and its postcondition is unsatisfied — using allowed administrator fallback once"
            )
        } else {
            AppLogger.shared.log(
                "⚠️ [Router] \(operation) helper failed and its postcondition is unsatisfied — using allowed administrator fallback once"
            )
        }
        try await fallback()
        try await enforcePostcondition()
    }

    private func enforceKanataRuntimePostcondition(after operation: String) async throws {
        // Matrix rows: helper/sudo command success is not repair success.
        // Runtime-mutating operations must prove ready or explicit pending
        // approval before callers see success.
        let readiness = await verifyKanataReadinessAfterInstall(context: operation)
        guard readiness.isSuccess else {
            throw PrivilegedOperationError.operationFailed(
                "Kanata postcondition failed after \(operation): \(readiness.failureDescription)"
            )
        }
    }

    private func enforceNewsyslogPostcondition(after operation: String) throws {
        guard verifyNewsyslogPostcondition() else {
            throw PrivilegedOperationError.operationFailed(
                "Newsyslog config postcondition failed after \(operation)"
            )
        }
    }

    private func verifyNewsyslogPostcondition() -> Bool {
        #if DEBUG
            if let override = Self.newsyslogPostconditionOverride {
                return override()
            }
        #endif
        return ServiceBootstrapper.shared.isNewsyslogConfigInstalled()
    }

    private func enforceVHIDServicesPostcondition(after operation: String) async throws {
        // Matrix rows: helper path succeeds / sudo fallback succeeds. Both
        // paths share the same VHID service postcondition instead of trusting
        // command completion.
        guard await verifyVHIDServicesPostcondition(context: operation) else {
            throw PrivilegedOperationError.operationFailed(
                "VHID services postcondition failed after \(operation)"
            )
        }
    }

    private func enforceVHIDDriverPostcondition(after operation: String) async throws {
        guard await verifyVHIDDriverPostcondition(context: operation) else {
            throw PrivilegedOperationError.operationFailed(
                "VHID driver postcondition failed after \(operation)"
            )
        }
    }

    private func enforceProcessTerminatedPostcondition(pid: Int32, after operation: String) async throws {
        guard await verifyProcessTerminatedPostcondition(pid: pid, context: operation) else {
            throw PrivilegedOperationError.operationFailed(
                "Process termination postcondition failed after \(operation) for PID \(pid)"
            )
        }
    }

    private func enforceKanataStoppedPostcondition(after operation: String) async throws {
        guard await verifyKanataStoppedPostcondition(context: operation) else {
            throw PrivilegedOperationError.operationFailed(
                "Kanata stopped postcondition failed after \(operation)"
            )
        }
    }

    private func verifyVHIDServicesPostcondition(context: String) async -> Bool {
        #if DEBUG
            if let override = Self.vhidServicesPostconditionOverride {
                return await override(context)
            }
        #endif

        let deadline = Date().addingTimeInterval(Self.vhidVerifyTimeoutSeconds)
        repeat {
            serviceHealthChecker.invalidateHealthCache()
            let status = await serviceHealthChecker.getServiceStatus()
            let configured = serviceHealthChecker.isVHIDDaemonConfiguredCorrectly()
            if status.vhidDaemonServiceLoaded,
               status.vhidManagerServiceLoaded,
               status.vhidDaemonServiceHealthy,
               status.vhidManagerServiceHealthy,
               configured
            {
                return true
            }
            do { try await Task.sleep(for: Self.postconditionPollInterval) }
            catch { return false }
        } while Date() < deadline

        AppLogger.shared.warnUnlessQuietTest(
            "⚠️ [PrivilegedOperationsRouter] VHID services postcondition failed after \(context)"
        )
        return false
    }

    private func verifyVHIDDriverPostcondition(context: String) async -> Bool {
        #if DEBUG
            if let override = Self.vhidDriverPostconditionOverride {
                return await override(context)
            }
        #endif

        switch await serviceHealthChecker.vhidDriverExtensionStatus() {
        case .enabled:
            return true
        case .installedButNotEnabled:
            AppLogger.shared.warnUnlessQuietTest(
                "⚠️ [PrivilegedOperationsRouter] VHID driver installed but not enabled after \(context); user approval may be required"
            )
            return true
        case .missing, .unknown:
            AppLogger.shared.warnUnlessQuietTest(
                "⚠️ [PrivilegedOperationsRouter] VHID driver postcondition failed after \(context)"
            )
            return false
        }
    }

    private func verifyProcessTerminatedPostcondition(pid: Int32, context: String) async -> Bool {
        #if DEBUG
            if let override = Self.processTerminatedPostconditionOverride {
                return await override(pid, context)
            }
        #endif

        let deadline = Date().addingTimeInterval(Self.processTerminationVerifyTimeoutSeconds)
        repeat {
            if !SystemStateProvider.isProcessAlive(pid: pid) {
                return true
            }
            do { try await Task.sleep(for: Self.postconditionPollInterval) }
            catch { return false }
        } while Date() < deadline

        AppLogger.shared.warnUnlessQuietTest(
            "⚠️ [PrivilegedOperationsRouter] Process \(pid) still alive after \(context)"
        )
        return false
    }

    private func verifyKanataStoppedPostcondition(context: String) async -> Bool {
        #if DEBUG
            if let override = Self.kanataStoppedPostconditionOverride {
                return await override(context)
            }
        #endif

        let deadline = Date().addingTimeInterval(Self.kanataStopVerifyTimeoutSeconds)
        repeat {
            let pids = await SystemStateProvider.shared.processIDs(matching: "kanata.*--cfg")
            if pids.isEmpty { return true }
            do { try await Task.sleep(for: Self.postconditionPollInterval) }
            catch { return false }
        } while Date() < deadline

        AppLogger.shared.warnUnlessQuietTest(
            "⚠️ [PrivilegedOperationsRouter] Kanata still running after \(context)"
        )
        return false
    }

    private func verifyKanataReadinessAfterInstall(context: String) async -> KanataReadinessResult {
        #if DEBUG
            if let override = Self.kanataReadinessOverride {
                return await override(context)
            }
        #endif

        let managementState = await currentServiceState()
        if managementState == .smappservicePending {
            return .pendingApproval
        }

        let staleOnEntry = if managementState == .smappserviceActive {
            await kanataDaemonManager.isRegisteredButNotLoaded()
        } else {
            false
        }
        if staleOnEntry { return .staleRegistration }

        let deadline = Date().addingTimeInterval(Self.kanataReadinessTimeout)
        var launchctlNotFoundSamples: [Bool] = []

        while Date() < deadline {
            if Task.isCancelled { return .timedOut }

            let remaining = deadline.timeIntervalSince(Date())
            let timeoutMs = max(50, min(300, Int(remaining * 1000)))
            let wizardState = WizardServiceManagementState(managementState)
            let snapshot = await serviceHealthChecker.checkKanataServiceRuntimeSnapshot(
                managementState: wizardState,
                staleEnabledRegistration: false,
                timeoutMs: timeoutMs
            )

            if snapshot.isRunning, snapshot.isResponding, snapshot.inputCaptureReady {
                return .ready
            }

            let notFound =
                snapshot.launchctlExitCode == Self.kanataLaunchctlNotFoundExitCode
                    && !snapshot.isRunning && !snapshot.isResponding
            launchctlNotFoundSamples.append(notFound)
            if launchctlNotFoundSamples.count > 5 {
                launchctlNotFoundSamples.removeFirst(launchctlNotFoundSamples.count - 5)
            }
            let notFoundCount = launchctlNotFoundSamples.filter(\.self).count

            if notFoundCount >= Self.persistentLaunchctlNotFoundThreshold,
               !snapshot.recentlyRestarted
            {
                return .launchctlNotFoundPersistent
            }

            let sleepSeconds = min(
                Self.kanataReadinessPollIntervalSeconds,
                max(0, deadline.timeIntervalSince(Date()))
            )
            if sleepSeconds > 0 {
                do { try await Task.sleep(for: .seconds(sleepSeconds)) }
                catch is CancellationError { return .timedOut }
                catch {}
            }
        }

        if await detectKanataTCPPortConflict() { return .tcpPortInUse }
        return .timedOut
    }

    private func detectKanataTCPPortConflict() async -> Bool {
        let result: ProcessResult
        do {
            result = try await subprocessRunner.run(
                "/usr/sbin/lsof", args: ["-nP", "-iTCP:\(KeyPathConstants.Networking.defaultTCPPort)", "-sTCP:LISTEN"], timeout: 2.0
            )
        } catch { return false }
        guard result.exitCode == 0 else { return false }
        let output = result.stdout.lowercased()
        return output.contains("kanata")
    }

    private func removeLegacyKanataPlist(reason _: String) async {
        let path = KanataDaemonManager.legacyPlistPath
        guard Foundation.FileManager().fileExists(atPath: path) else { return }
        guard path.hasPrefix("/Library/LaunchDaemons/"),
              path.hasSuffix(".plist"),
              !path.contains("'"), !path.contains("\\"), !path.contains(";"),
              !path.contains("&"), !path.contains("|"), !path.contains("`"),
              !path.contains("$"), !path.contains("\n")
        else { return }

        let cmd = """
        /bin/launchctl bootout system/\(KanataDaemonManager.kanataServiceID) 2>/dev/null || true && \
        /bin/rm -f '\(path)'
        """
        do { try await sudoExecuteCommand(cmd, description: "Remove legacy Kanata plist") }
        catch {}
    }

    private func helperRestartKarabinerDaemonVerified() async throws -> Bool {
        do { try await helperManager.restartKarabinerDaemon() }
        catch {}

        do { try await helperManager.recoverRequiredRuntimeServices() }
        catch {}

        let vhidManager = VHIDDeviceManager()
        let start = Date()
        while Date().timeIntervalSince(start) < Self.vhidVerifyTimeoutSeconds {
            if await vhidManager.detectRunning() { return true }
            try await Task.sleep(for: Self.postconditionPollInterval)
        }

        try await Task.sleep(for: Self.vhidSettleDelay)
        return await vhidManager.detectRunning()
    }

    private func sudoRestartKarabinerDaemonVerified() async throws -> Bool {
        let vhidLabel = "com.keypath.karabiner-vhiddaemon"
        let vhidPlist = "/Library/LaunchDaemons/\(vhidLabel).plist"
        let daemonPath =
            "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"

        let hasService = Foundation.FileManager().fileExists(atPath: vhidPlist)
        var commands: [String] = []

        if hasService {
            commands.append("""
            /bin/launchctl bootout system/\(vhidLabel) 2>/dev/null || true
            /bin/launchctl disable system/\(vhidLabel) 2>/dev/null || true
            """)
        }

        commands.append("""
        /usr/bin/pkill -f "Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
        /bin/sleep 0.15
        /usr/bin/pkill -9 -f "Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
        /bin/sleep 0.15
        """)

        if hasService {
            commands.append("""
            /bin/launchctl enable system/\(vhidLabel) 2>/dev/null || true
            kp_timeout 15 /bin/launchctl kickstart -k system/\(vhidLabel)
            """)
        } else {
            commands.append("'\(daemonPath)' > /dev/null 2>&1 &")
        }

        let batch = PrivilegedCommandRunner.Batch(
            label: "restart VirtualHID daemon",
            commands: commands,
            prompt: "KeyPath needs to restart the VirtualHID daemon."
        )

        do { try await sudoExecuteBatch(batch) }
        catch { return false }

        let vhidManager = VHIDDeviceManager()
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < Self.vhidVerifyTimeoutSeconds {
            if await vhidManager.detectRunning() { return true }
            try await Task.sleep(for: Self.postconditionPollInterval)
        }

        return false
    }

    private static func notifySMAppServiceApprovalRequired(context _: String) {
        let now = Date()
        if let last = lastSMAppApprovalNotice,
           now.timeIntervalSince(last) < smAppApprovalNoticeThrottle
        { return }
        lastSMAppApprovalNotice = now
        NotificationCenter.default.post(name: .smAppServiceApprovalRequired, object: nil)
    }
}

extension PrivilegedOperationsRouter: PrivilegedOperationsCoordinating {}

// MARK: - Test SPI

#if DEBUG
    @_spi(ServiceInstallTesting)
    extension PrivilegedOperationsRouter {
        func _testEnsureServices(context: String) async throws -> Bool {
            try await installServicesIfUninstalled(context: context)
        }

        static func _testResetServiceInstallGuard() {
            serviceStateOverride = nil
            installAllServicesOverride = nil
            lastServiceInstallAttempt = nil
            ServiceInstallGuard.reset()
        }

        static func _testDecideInstallGuard(
            state: KanataDaemonManager.ServiceManagementState,
            staleEnabledRegistration: Bool,
            now: Date = Date(),
            lastAttempt: Date? = nil
        ) -> ServiceInstallGuard.Decision {
            ServiceInstallGuard.decide(
                state: state,
                staleEnabledRegistration: staleEnabledRegistration,
                now: now,
                lastAttempt: lastAttempt
            )
        }
    }
#endif
