import AppKit
import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathWizardCore

@MainActor
protocol PrivilegedOperationsCoordinating: WizardPrivilegedOperating {}

/// Routes privileged operations to either the XPC helper (release) or direct sudo (debug).
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
    private static let smAppApprovalNoticeThrottle: TimeInterval = 5

    private static let kanataReadinessTimeout: TimeInterval = 20
    private static let kanataReadinessPollIntervalSeconds: TimeInterval = 0.5
    private static let kanataLaunchctlNotFoundExitCode: Int32 = 113
    private static let persistentLaunchctlNotFoundThreshold = 3

    private static let vhidVerifyTimeoutSeconds: Double = 1.5
    private static let vhidVerifyInterval: Duration = .milliseconds(100)
    private static let vhidSettleDelay: Duration = .milliseconds(150)

    #if DEBUG
        nonisolated(unsafe) static var serviceStateOverride:
            (() -> KanataDaemonManager.ServiceManagementState)?
        nonisolated(unsafe) static var installAllServicesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var recoverRequiredRuntimeServicesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var killExistingKanataProcessesOverride: (() async throws -> Void)?
        nonisolated(unsafe) static var kanataReadinessOverride:
            ((String) async -> KanataReadinessResult)?

        static func resetTestingState() {
            serviceStateOverride = nil
            installAllServicesOverride = nil
            recoverRequiredRuntimeServicesOverride = nil
            killExistingKanataProcessesOverride = nil
            kanataReadinessOverride = nil
            lastServiceInstallAttempt = nil
            lastSMAppApprovalNotice = nil
            ServiceInstallGuard.reset()
            KanataDaemonManager.registeredButNotLoadedOverride = nil
            ServiceHealthChecker.runtimeSnapshotOverride = nil
        }
    #endif

    enum OperationMode {
        case privilegedHelper
        case directSudo
    }

    static var operationMode: OperationMode {
        #if DEBUG
            return .directSudo
        #else
            return .privilegedHelper
        #endif
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
        switch Self.operationMode {
        case .privilegedHelper:
            do {
                try await helperManager.installRequiredRuntimeServices()
            } catch {
                try await sudoInstallRequiredRuntimeServices()
            }
        case .directSudo:
            try await sudoInstallRequiredRuntimeServices()
        }
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
                try await helperManager.recoverRequiredRuntimeServices()
            } catch {
                try await sudoRestartServices()
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
        case let .run(_, _):
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
            do { try await helperManager.installNewsyslogConfig() }
            catch { try await sudoInstallNewsyslogConfig() }
        case .directSudo:
            try await sudoInstallNewsyslogConfig()
        }
    }

    public func repairVHIDDaemonServices() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            // Check helper responsiveness first to avoid 30s XPC timeout
            // when the helper isn't installed or isn't responding.
            let helperWorking = await helperManager.testHelperFunctionality()
            if helperWorking {
                do { try await helperManager.repairVHIDDaemonServices() }
                catch { try await sudoRepairVHIDServices() }
            } else {
                AppLogger.shared.log("⚠️ [Router] Helper not responsive — using sudo for VHID repair")
                try await sudoRepairVHIDServices()
            }
        case .directSudo:
            try await sudoRepairVHIDServices()
        }
    }

    public func activateVirtualHIDManager() async throws {
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
        switch Self.operationMode {
        case .privilegedHelper:
            do {
                let bundledPkgPath = WizardSystemPaths.bundledVHIDDriverPkgPath
                guard WizardSystemPaths.bundledVHIDDriverPkgExists else {
                    throw PrivilegedOperationError.operationFailed(
                        "Bundled VHID driver package not found."
                    )
                }
                try await helperManager.installBundledVHIDDriver(pkgPath: bundledPkgPath)
            } catch {
                try await sudoInstallCorrectDriver()
            }
        case .directSudo:
            try await sudoInstallCorrectDriver()
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
            do { try await helperManager.terminateProcess(pid) }
            catch { try await sudoTerminateProcess(pid: pid) }
        case .directSudo:
            try await sudoTerminateProcess(pid: pid)
        }
    }

    public func killAllKanataProcesses() async throws {
        switch Self.operationMode {
        case .privilegedHelper:
            do { try await helperManager.killAllKanataProcesses() }
            catch { try await sudoKillAllKanata() }
        case .directSudo:
            try await sudoKillAllKanata()
        }
    }

    public func restartKarabinerDaemonVerified() async throws -> Bool {
        switch Self.operationMode {
        case .privilegedHelper:
            return try await helperRestartKarabinerDaemonVerified()
        case .directSudo:
            return try await sudoRestartKarabinerDaemonVerified()
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
        let success = await ServiceBootstrapper.shared.installAllServices()
        if !success {
            throw PrivilegedOperationError.installationFailed("Required runtime service installation failed")
        }
    }

    private func sudoRestartServices() async throws {
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
        let success = await ServiceBootstrapper.shared.installNewsyslogConfig()
        if !success {
            throw PrivilegedOperationError.operationFailed("Newsyslog config installation failed")
        }
    }

    private func sudoRepairVHIDServices() async throws {
        let success = await ServiceBootstrapper.shared.repairVHIDDaemonServices()
        if !success {
            throw PrivilegedOperationError.operationFailed("VHID daemon repair failed")
        }
    }

    private func sudoActivateVHID() async throws {
        let vhidManager = VHIDDeviceManager()
        if !(await vhidManager.activateManager()) {
            throw PrivilegedOperationError.operationFailed("VirtualHID activation failed")
        }
    }

    private func sudoUninstallDrivers() async throws {
        let vhidManager = VHIDDeviceManager()
        if !(await vhidManager.uninstallAllDriverVersions()) {
            throw PrivilegedOperationError.operationFailed("Driver uninstallation failed")
        }
    }

    private func sudoInstallCorrectDriver() async throws {
        let vhidManager = VHIDDeviceManager()
        if !(await vhidManager.downloadAndInstallCorrectVersion()) {
            throw PrivilegedOperationError.operationFailed("Driver installation failed")
        }
    }

    private func sudoTerminateProcess(pid: Int32) async throws {
        do {
            try await sudoExecuteCommand("/bin/kill -TERM \(pid)", description: "Terminate process \(pid)")
        } catch {
            try await sudoExecuteCommand("/bin/kill -9 \(pid)", description: "Force kill process \(pid)")
        }
    }

    private func sudoKillAllKanata() async throws {
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

    private func killExistingKanataProcessesForServiceRecovery() async throws {
        #if DEBUG
            if let override = Self.killExistingKanataProcessesOverride {
                try await override()
                return
            }
        #endif

        switch Self.operationMode {
        case .privilegedHelper:
            do { try await helperManager.killAllKanataProcesses() }
            catch { try await sudoKillAllKanata() }
        case .directSudo:
            try await sudoKillAllKanata()
        }
    }

    private func enforceKanataRuntimePostcondition(after operation: String) async throws {
        let readiness = await verifyKanataReadinessAfterInstall(context: operation)
        guard readiness.isSuccess else {
            throw PrivilegedOperationError.operationFailed(
                "Kanata postcondition failed after \(operation): \(readiness.failureDescription)"
            )
        }
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
                "/usr/sbin/lsof", args: ["-nP", "-iTCP:37001", "-sTCP:LISTEN"], timeout: 2.0
            )
        } catch { return false }
        guard result.exitCode == 0 else { return false }
        let output = result.stdout.lowercased()
        return output.contains("kanata")
    }

    private func removeLegacyKanataPlist(reason: String) async {
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
            try await Task.sleep(for: Self.vhidVerifyInterval)
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
            /bin/launchctl kickstart -k system/\(vhidLabel)
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
            try await Task.sleep(for: Self.vhidVerifyInterval)
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
