import AppKit
import Foundation
import KeyPathCore

/// Coordinates all privileged operations with hybrid approach (helper vs direct sudo)
///
/// **Architecture:** This coordinator implements the hybrid strategy from HELPER.md
/// - DEBUG builds: Use direct sudo (AuthorizationExecuteWithPrivileges)
/// - RELEASE builds: Prefer privileged helper; fall back to sudo on failure
///
/// **Usage:**
/// ```swift
/// let coordinator = PrivilegedOperationsCoordinator.shared
/// try await coordinator.installLaunchDaemon(plistPath: path, serviceID: id)
/// ```
@MainActor
final class PrivilegedOperationsCoordinator {
    private static let serviceGuardLogPrefix = "[ServiceInstallGuard]"
    private static let serviceInstallThrottle: TimeInterval = 30
    private static var lastServiceInstallAttempt: Date?
    private static var lastSMAppApprovalNotice: Date?
    private static let smAppApprovalNoticeThrottle: TimeInterval = 5

    #if DEBUG
        nonisolated(unsafe) static var serviceStateOverride:
            (() -> KanataDaemonManager.ServiceManagementState)?
        nonisolated(unsafe) static var installAllServicesOverride: (() async throws -> Void)?
    #endif

    // MARK: - Singleton

    static let shared = PrivilegedOperationsCoordinator()

    private init() {
        AppLogger.shared.log(
            "🔐 [PrivCoordinator] Initialized with operation mode: \(Self.operationMode)")
    }

    // MARK: - Operation Modes

    enum OperationMode {
        case privilegedHelper // XPC to root daemon (future: Phase 2)
        case directSudo // AuthorizationExecuteWithPrivileges (current)
    }

    /// Determine which operation mode to use based on build configuration
    static var operationMode: OperationMode {
        #if DEBUG
            // Debug builds always use direct sudo for easy contributor testing
            return .directSudo
        #else
            // Release builds prefer helper by default; callers will fall back on errors
            return .privilegedHelper
        #endif
    }

    // MARK: - Unified Privileged Operations API

    // MARK: LaunchDaemon Operations

    /// Install a LaunchDaemon plist file to /Library/LaunchDaemons/
    func installLaunchDaemon(plistPath: String, serviceID: String) async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Installing LaunchDaemon: \(serviceID)")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallLaunchDaemon(plistPath: plistPath, serviceID: serviceID)
        case .directSudo:
            try await sudoInstallLaunchDaemon(plistPath: plistPath, serviceID: serviceID)
        }
    }

    /// Remove any installed SMJobBless helper and its daemon plist/logs (developer convenience)
    func cleanupPrivilegedHelper() async throws {
        AppLogger.shared.log("🧹 [PrivCoordinator] Cleaning up privileged helper (dev)")

        // Use tolerant chain so cleanup succeeds even if some files are absent
        let cmd = """
        /bin/launchctl bootout system/com.keypath.helper || true; \
        /bin/rm -f /Library/LaunchDaemons/com.keypath.helper.plist || true; \
        /bin/rm -f /Library/PrivilegedHelperTools/com.keypath.helper || true; \
        /bin/rm -f /var/log/com.keypath.helper.stdout.log /var/log/com.keypath.helper.stderr.log || true
        """

        try await sudoExecuteCommand(cmd, description: "Cleanup privileged helper")
        AppLogger.shared.log("✅ [PrivCoordinator] Cleanup completed")
    }

    /// Install all LaunchDaemon services with explicit parameters
    func installAllLaunchDaemonServices(
        kanataBinaryPath: String,
        kanataConfigPath: String,
        tcpPort: Int
    ) async throws {
        AppLogger.shared.log(
            "🔐 [PrivCoordinator] Installing all LaunchDaemon services via SMAppService")
        // Always use SMAppService path for Kanata
        try await sudoInstallAllServices(
            kanataBinaryPath: kanataBinaryPath,
            kanataConfigPath: kanataConfigPath,
            tcpPort: tcpPort
        )
    }

    /// Install all LaunchDaemon services (convenience overload - uses PreferencesService for config)
    func installAllLaunchDaemonServices() async throws {
        AppLogger.shared.log(
            "🔐 [PrivCoordinator] Installing all LaunchDaemon services (using preferences) via SMAppService"
        )
        // Always use SMAppService path for Kanata
        try await sudoInstallAllServicesWithPreferences()
    }

    private func currentServiceState() async -> KanataDaemonManager.ServiceManagementState {
        #if DEBUG
            if let override = Self.serviceStateOverride {
                return override()
            }
        #endif
        return await KanataDaemonManager.shared.refreshManagementState()
    }

    private func runServiceInstall() async throws {
        #if DEBUG
            if let override = Self.installAllServicesOverride {
                try await override()
                return
            }
        #endif
        try await installAllLaunchDaemonServices()
    }

    /// Restart unhealthy LaunchDaemon services
    func restartUnhealthyServices() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Restarting unhealthy services")

        // If the Kanata service is completely uninstalled, install everything first.
        if try await installServicesIfUninstalled(context: "pre-restart") {
            AppLogger.shared.log(
                "✅ [PrivCoordinator] Installed services before restart request – skipping restart call")
            return
        }

        try await sudoRestartServices()

        // Double-check after restart – helper path cannot install SMAppService jobs.
        if try await installServicesIfUninstalled(context: "post-restart") {
            AppLogger.shared.log("✅ [PrivCoordinator] Service installed after restart attempt")
        }
    }

    /// Installs all LaunchDaemon services via SMAppService when the Kanata daemon is missing.
    /// - Returns: `true` if installation was performed.
    @discardableResult
    func installServicesIfUninstalled(context: String) async throws -> Bool {
        let state = await currentServiceState()
        AppLogger.shared.log("\(Self.serviceGuardLogPrefix) \(context): state=\(state.description)")

        if state == .smappservicePending {
            Self.notifySMAppServiceApprovalRequired(context: context)
            AppLogger.shared.log("\(Self.serviceGuardLogPrefix) \(context): approval pending - skipping install/refresh")
            return false
        }

        let requiresInstall = state.needsInstallation || state.needsMigration()

        guard requiresInstall else {
            AppLogger.shared.log("\(Self.serviceGuardLogPrefix) \(context): no install needed")
            return false
        }

        if state.needsMigration() {
            await removeLegacyKanataPlist(reason: context)
        }

        let now = Date()
        if let last = Self.lastServiceInstallAttempt,
           now.timeIntervalSince(last) < Self.serviceInstallThrottle
        {
            let remaining = Self.serviceInstallThrottle - now.timeIntervalSince(last)
            AppLogger.shared.log(
                "\(Self.serviceGuardLogPrefix) \(context): skipping auto-install (throttled, \(String(format: "%.1f", remaining))s remaining)"
            )
            return false
        }

        Self.lastServiceInstallAttempt = now
        AppLogger.shared.log("\(Self.serviceGuardLogPrefix) \(context): running SMAppService install")
        try await runServiceInstall()
        let postInstallState = await currentServiceState()
        AppLogger.shared.log(
            "\(Self.serviceGuardLogPrefix) \(context): install complete, new state=\(postInstallState.description)"
        )
        return true
    }

    /// Regenerate service configuration with current settings
    func regenerateServiceConfiguration() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Regenerating service configuration via SMAppService")
        // Always use SMAppService path for Kanata
        try await sudoRegenerateConfig()
    }

    /// Install log rotation service
    func installLogRotation() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Installing log rotation")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallLogRotation()
        case .directSudo:
            try await sudoInstallLogRotation()
        }
    }

    /// Repair VirtualHID daemon LaunchDaemon services
    func repairVHIDDaemonServices() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Repairing VHID daemon services")

        switch Self.operationMode {
        case .privilegedHelper:
            do { try await helperRepairVHIDServices() } catch {
                AppLogger.shared.log(
                    "🚨 [PrivCoordinator] FALLBACK: helper repairVHIDDaemonServices failed: \(error.localizedDescription). Using AppleScript/sudo path."
                )
                try await sudoRepairVHIDServices()
            }
        case .directSudo:
            try await sudoRepairVHIDServices()
        }
    }

    /// Install LaunchDaemon services without loading them (for adopting orphaned processes)
    func installLaunchDaemonServicesWithoutLoading() async throws {
        AppLogger.shared.log(
            "🔐 [PrivCoordinator] Installing LaunchDaemon services (install-only, no load)")

        switch Self.operationMode {
        case .privilegedHelper:
            do { try await helperInstallServicesWithoutLoading() } catch {
                AppLogger.shared.log(
                    "🚨 [PrivCoordinator] FALLBACK: helper installLaunchDaemonServicesWithoutLoading failed: \(error.localizedDescription). Using AppleScript/sudo path."
                )
                try await sudoInstallServicesWithoutLoading()
            }
        case .directSudo:
            try await sudoInstallServicesWithoutLoading()
        }
    }

    // MARK: VirtualHID Operations

    /// Activate VirtualHID Manager
    func activateVirtualHIDManager() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Activating VirtualHID Manager")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperActivateVHID()
        case .directSudo:
            try await sudoActivateVHID()
        }
    }

    /// Uninstall all VirtualHID driver versions
    func uninstallVirtualHIDDrivers() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Uninstalling VirtualHID drivers")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperUninstallDrivers()
        case .directSudo:
            try await sudoUninstallDrivers()
        }
    }

    /// Download and install specific VirtualHID driver version
    func installVirtualHIDDriver(version: String, downloadURL: String) async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Installing VirtualHID driver v\(version)")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallDriver(version: version, downloadURL: downloadURL)
        case .directSudo:
            try await sudoInstallDriver(version: version, downloadURL: downloadURL)
        }
    }

    /// Download and install correct VirtualHID driver version (convenience method)
    /// Uses VHIDDeviceManager to determine the correct version automatically
    ///
    /// **Automatic Fallback:** In release mode, attempts helper first, then falls back
    /// to sudo if helper fails. This handles phantom registrations and XPC issues gracefully.
    func downloadAndInstallCorrectVHIDDriver() async throws {
        AppLogger.shared.log(
            "🔐 [PrivCoordinator] Downloading and installing correct VHID driver version")

        switch Self.operationMode {
        case .privilegedHelper:
            do {
                // Try helper first
                try await helperInstallCorrectDriver()
                AppLogger.shared.log("✅ [PrivCoordinator] Helper successfully installed driver")
            } catch {
                AppLogger.shared.log("⚠️ [PrivCoordinator] Helper failed (\(error)), falling back to sudo")
                // Automatic fallback to sudo - catches phantom registrations and XPC failures
                try await sudoInstallCorrectDriver()
                AppLogger.shared.log("✅ [PrivCoordinator] Sudo fallback successfully installed driver")
            }
        case .directSudo:
            try await sudoInstallCorrectDriver()
        }
    }

    // MARK: Process Management Operations

    /// Terminate a process by PID
    func terminateProcess(pid: Int32) async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Terminating process PID=\(pid)")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperTerminateProcess(pid: pid)
        case .directSudo:
            try await sudoTerminateProcess(pid: pid)
        }
    }

    /// Kill all Kanata processes
    func killAllKanataProcesses() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Killing all Kanata processes")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperKillAllKanata()
        case .directSudo:
            try await sudoKillAllKanata()
        }
    }

    // Removed: legacy non-verified restart. Use restartKarabinerDaemonVerified() instead.

    /// Restart Karabiner VirtualHID daemon with verification (kill all + start + verify)
    /// Returns true if restart succeeded and daemon is healthy, false otherwise
    func restartKarabinerDaemonVerified() async throws -> Bool {
        AppLogger.shared.log("🔐 [PrivCoordinator] Restarting Karabiner daemon (verified)")

        switch Self.operationMode {
        case .privilegedHelper:
            return try await helperRestartKarabinerDaemonVerified()
        case .directSudo:
            return try await sudoRestartKarabinerDaemonVerified()
        }
    }

    // MARK: Generic Execute

    /// Install the bundled Kanata binary to the system location
    func installBundledKanata() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Installing bundled Kanata binary")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallBundledKanata()
        case .directSudo:
            try await sudoInstallBundledKanata()
        }

        // Ensure SMAppService launchd job exists after installing the binary
        // (common case: fresh reinstall leaves service missing even though binary is present)
        try await installServicesIfUninstalled(context: "installBundledKanata")
    }

    // Note: executeCommand removed for security. All privileged operations
    // must be explicitly defined. Internal sudoExecuteCommand remains for
    // implementation of specific operations.

    // MARK: - Privileged Helper Path (Phase 2 - Future Implementation)

    private func helperInstallLaunchDaemon(plistPath: String, serviceID: String) async throws {
        try await HelperManager.shared.installLaunchDaemon(plistPath: plistPath, serviceID: serviceID)
    }

    private func helperRegenerateConfig() async throws {
        AppLogger.shared.log("🔧 [PrivCoordinator] Bypassing helper - using SMAppService path directly")
        // Always use SMAppService path for Kanata (helper doesn't support SMAppService)
        try await sudoRegenerateConfig()
    }

    private func helperInstallLogRotation() async throws {
        do {
            try await HelperManager.shared.installLogRotation()
        } catch {
            let msg: String = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            if msg.localizedCaseInsensitiveContains("not yet implemented") {
                AppLogger.shared.log(
                    "🚨 [PrivCoordinator] FALLBACK: helper installLogRotation not implemented. Using AppleScript/sudo path."
                )
                try await sudoInstallLogRotation()
            } else {
                throw error
            }
        }
    }

    private func helperRepairVHIDServices() async throws {
        do {
            try await HelperManager.shared.repairVHIDDaemonServices()
        } catch {
            let msg: String = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            if msg.localizedCaseInsensitiveContains("not yet implemented") {
                AppLogger.shared.log(
                    "🚨 [PrivCoordinator] FALLBACK: helper repairVHIDDaemonServices not implemented. Using AppleScript/sudo path."
                )
                try await sudoRepairVHIDServices()
            } else {
                throw error
            }
        }
    }

    private func removeLegacyKanataPlist(reason: String) async {
        let path = KanataDaemonManager.legacyPlistPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        AppLogger.shared.log("🧹 [PrivCoordinator] Removing legacy Kanata plist (reason: \(reason))")
        let cmd = """
        /bin/launchctl bootout system/\(KanataDaemonManager.kanataServiceID) 2>/dev/null || true && \
        /bin/rm -f '\(path)'
        """
        do {
            try await sudoExecuteCommand(cmd, description: "Remove legacy Kanata plist")
        } catch {
            AppLogger.shared.log("⚠️ [PrivCoordinator] Failed to remove legacy Kanata plist: \(error)")
        }
    }

    private func helperInstallServicesWithoutLoading() async throws {
        try await HelperManager.shared.installLaunchDaemonServicesWithoutLoading()
    }

    private func helperActivateVHID() async throws {
        try await HelperManager.shared.activateVirtualHIDManager()
    }

    private func helperUninstallDrivers() async throws {
        try await HelperManager.shared.uninstallVirtualHIDDrivers()
    }

    private func helperInstallDriver(version: String, downloadURL: String) async throws {
        try await HelperManager.shared.installVirtualHIDDriver(
            version: version, downloadURL: downloadURL
        )
    }

    private func helperInstallCorrectDriver() async throws {
        try await HelperManager.shared.downloadAndInstallCorrectVHIDDriver()
    }

    private func helperTerminateProcess(pid: Int32) async throws {
        try await HelperManager.shared.terminateProcess(pid)
    }

    /// Terminate a process (helper-first; fallback to sudo with explicit logs)
    func terminateProcess(_ pid: Int32) async throws {
        do {
            AppLogger.shared.log("🔐 [PrivCoordinator] Helper-first terminate PID=\(pid)")
            try await helperTerminateProcess(pid: pid)
        } catch {
            AppLogger.shared.log(
                "🚨 [PrivCoordinator] FALLBACK: helper terminateProcess failed for PID=\(pid): \(error.localizedDescription). Using AppleScript/sudo path."
            )
            try await sudoTerminateProcess(pid: pid)
        }
    }

    private func helperKillAllKanata() async throws {
        try await HelperManager.shared.killAllKanataProcesses()
    }

    // Removed: legacy helper restart. Verified path must be used.

    private func helperRestartKarabinerDaemonVerified() async throws -> Bool {
        AppLogger.shared.log("🔐 [PrivCoordinator] Helper path: verified restart of Karabiner daemon")

        // Snapshot PRE state (using extracted ServiceHealthChecker)
        let preLoaded = await ServiceHealthChecker.shared.isServiceLoaded(
            serviceID: "com.keypath.karabiner-vhiddaemon")
        let preHealth = await ServiceHealthChecker.shared.isServiceHealthy(
            serviceID: "com.keypath.karabiner-vhiddaemon")
        AppLogger.shared.log(
            "🔎 [PrivCoordinator] PRE: vhiddaemon loaded=\(preLoaded), healthy=\(preHealth)")

        // 1) Kill any running VirtualHIDDevice daemons via helper (root)
        do {
            try await HelperManager.shared.restartKarabinerDaemon()
        } catch {
            AppLogger.shared.log(
                "⚠️ [PrivCoordinator] Helper kill phase returned error (continuing): \(error.localizedDescription)"
            )
        }

        // 2) Ask helper to restart unhealthy services or install if missing
        do {
            try await HelperManager.shared.restartUnhealthyServices()
        } catch {
            AppLogger.shared.log(
                "⚠️ [PrivCoordinator] Helper restartUnhealthyServices failed: \(error.localizedDescription)")
        }

        // 3) Sustain verification loop (up to 3s) using our VHID manager health check
        let vhidManager = VHIDDeviceManager()
        let start = Date()
        while Date().timeIntervalSince(start) < 3.0 {
            if await vhidManager.detectRunning() {
                AppLogger.shared.log(
                    "✅ [PrivCoordinator] Verified: VirtualHIDDevice daemon healthy after helper restart")
                return true
            }
            try await Task.sleep(nanoseconds: 120_000_000) // 120ms
        }

        // 4) As a last resort, try a repair pass (installs/refreshes plists) then one more quick verify
        do {
            try await HelperManager.shared.repairVHIDDaemonServices()
        } catch {
            AppLogger.shared.log(
                "ℹ️ [PrivCoordinator] repairVHIDDaemonServices errored (may be okay): \(error.localizedDescription)"
            )
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        let postLoaded = await ServiceHealthChecker.shared.isServiceLoaded(
            serviceID: "com.keypath.karabiner-vhiddaemon")
        let postHealth = await ServiceHealthChecker.shared.isServiceHealthy(
            serviceID: "com.keypath.karabiner-vhiddaemon")
        AppLogger.shared.log(
            "🔎 [PrivCoordinator] POST: vhiddaemon loaded=\(postLoaded), healthy=\(postHealth)")
        if await vhidManager.detectRunning() {
            AppLogger.shared.log("✅ [PrivCoordinator] Verified after repair: daemon healthy")
            return true
        }

        AppLogger.shared.log("❌ [PrivCoordinator] Helper verified restart failed (daemon not healthy)")
        return false
    }

    private func helperInstallBundledKanata() async throws {
        do {
            try await HelperManager.shared.installBundledKanataBinaryOnly()
        } catch {
            let msg: String = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            AppLogger.shared.log(
                "🚨 [PrivCoordinator] Helper installBundledKanataBinaryOnly failed: \(msg). Falling back to sudo path."
            )
            try await sudoInstallBundledKanata()
        }
    }

    // MARK: - Karabiner Conflict Management

    func disableKarabinerGrabber() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Disabling Karabiner grabber via helper")
        try await HelperManager.shared.disableKarabinerGrabber()
    }

    // MARK: - Direct Sudo Path (Current Implementation)

    /// Install LaunchDaemon plist using osascript with admin privileges
    private func sudoInstallLaunchDaemon(plistPath: String, serviceID: String) async throws {
        let launchDaemonsPath = "/Library/LaunchDaemons"
        let finalPath = "\(launchDaemonsPath)/\(serviceID).plist"

        let command = """
        mkdir -p '\(launchDaemonsPath)' && \
        cp '\(plistPath)' '\(finalPath)' && \
        chown root:wheel '\(finalPath)' && \
        chmod 644 '\(finalPath)'
        """

        try await sudoExecuteCommand(
            command,
            description: "Install LaunchDaemon: \(serviceID)"
        )
    }

    /// Install all LaunchDaemon services using consolidated single-prompt method
    /// NOTE: Still uses LaunchDaemonInstaller - complex multi-service orchestration not yet extracted
    private func sudoInstallAllServices(
        kanataBinaryPath _: String,
        kanataConfigPath _: String,
        tcpPort _: Int
    ) async throws {
        // For now, this delegates to LaunchDaemonInstaller's existing implementation
        // Once we extract all the logic, we'll move it here
        let installer = LaunchDaemonInstaller()
        let success = await installer.createConfigureAndLoadAllServices()

        if !success {
            throw PrivilegedOperationError.installationFailed("LaunchDaemon installation failed")
        }
    }

    /// Install all LaunchDaemon services (convenience - uses PreferencesService)
    private func sudoInstallAllServicesWithPreferences() async throws {
        let installer = LaunchDaemonInstaller()
        let success = await installer.createConfigureAndLoadAllServices()

        if !success {
            throw PrivilegedOperationError.installationFailed("LaunchDaemon installation failed")
        }
    }

    /// Restart unhealthy services
    /// NOTE: Still uses LaunchDaemonInstaller - complex health/install orchestration not yet extracted
    private func sudoRestartServices() async throws {
        let installer = LaunchDaemonInstaller()
        let success = await installer.restartUnhealthyServices()

        if !success {
            throw PrivilegedOperationError.operationFailed("Service restart failed")
        }
    }

    /// Regenerate service configuration (SMAppService for Kanata)
    /// NOTE: Still uses LaunchDaemonInstaller - complex multi-service orchestration not yet extracted
    private func sudoRegenerateConfig() async throws {
        AppLogger.shared.log("🔧 [PrivCoordinator] Regenerating service configuration via SMAppService")
        let installer = LaunchDaemonInstaller()
        let success = await installer.createConfigureAndLoadAllServices()

        if !success {
            throw PrivilegedOperationError.operationFailed("Service regeneration via SMAppService failed")
        }
    }

    /// Install log rotation service
    /// Uses extracted ServiceBootstrapper
    private func sudoInstallLogRotation() async throws {
        let success = await ServiceBootstrapper.shared.installLogRotationService()

        if !success {
            throw PrivilegedOperationError.operationFailed("Log rotation installation failed")
        }
    }

    /// Repair VHID daemon services
    /// Uses extracted ServiceBootstrapper
    private func sudoRepairVHIDServices() async throws {
        let success = await ServiceBootstrapper.shared.repairVHIDDaemonServices()

        if !success {
            throw PrivilegedOperationError.operationFailed("VHID daemon repair failed")
        }
    }

    /// Install LaunchDaemon services without loading them (for orphan adoption)
    /// Uses extracted ServiceBootstrapper
    private func sudoInstallServicesWithoutLoading() async throws {
        let binaryPath = KanataBinaryInstaller.shared.getKanataBinaryPath()
        let success = await ServiceBootstrapper.shared.installAllServicesWithoutLoading(binaryPath: binaryPath)

        if !success {
            throw PrivilegedOperationError.operationFailed("Service installation (install-only) failed")
        }
    }

    /// Activate VirtualHID Manager using VHIDDeviceManager
    private func sudoActivateVHID() async throws {
        let vhidManager = VHIDDeviceManager()
        let success = await vhidManager.activateManager()

        if !success {
            throw PrivilegedOperationError.operationFailed("VirtualHID activation failed")
        }
    }

    /// Uninstall VirtualHID drivers using VHIDDeviceManager
    private func sudoUninstallDrivers() async throws {
        let vhidManager = VHIDDeviceManager()
        let success = await vhidManager.uninstallAllDriverVersions()

        if !success {
            throw PrivilegedOperationError.operationFailed("Driver uninstallation failed")
        }
    }

    /// Install VirtualHID driver using VHIDDeviceManager
    private func sudoInstallDriver(version _: String, downloadURL _: String) async throws {
        let vhidManager = VHIDDeviceManager()
        let success = await vhidManager.downloadAndInstallCorrectVersion()

        if !success {
            throw PrivilegedOperationError.operationFailed("Driver installation failed")
        }
    }

    /// Download and install correct VirtualHID driver version using VHIDDeviceManager
    private func sudoInstallCorrectDriver() async throws {
        let vhidManager = VHIDDeviceManager()
        let success = await vhidManager.downloadAndInstallCorrectVersion()

        if !success {
            throw PrivilegedOperationError.operationFailed("Driver installation failed")
        }
    }

    /// Terminate a process using kill command with admin privileges
    private func sudoTerminateProcess(pid: Int32) async throws {
        // Try SIGTERM first
        let termCommand = "/bin/kill -TERM \(pid)"

        do {
            try await sudoExecuteCommand(termCommand, description: "Terminate process \(pid)")
        } catch {
            // If SIGTERM fails, try SIGKILL
            AppLogger.shared.log("⚠️ [PrivCoordinator] SIGTERM failed, trying SIGKILL")
            let killCommand = "/bin/kill -9 \(pid)"
            try await sudoExecuteCommand(killCommand, description: "Force kill process \(pid)")
        }
    }

    /// Kill all Kanata processes
    private func sudoKillAllKanata() async throws {
        let command = "/usr/bin/pkill -f kanata"
        try await sudoExecuteCommand(command, description: "Kill all Kanata processes")
    }

    // Removed: legacy sudo restart. Verified path must be used.

    /// Restart Karabiner daemon with verification (kill all + start managed if possible + sustained verify)
    private func sudoRestartKarabinerDaemonVerified() async throws -> Bool {
        let daemonPath =
            "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
        let vhidLabel = "com.keypath.karabiner-vhiddaemon"
        let vhidPlist = "/Library/LaunchDaemons/\(vhidLabel).plist"

        // Determine if a LaunchDaemon is installed; prefer managed restart to prevent duplicates
        let hasService = FileManager.default.fileExists(atPath: vhidPlist)
        AppLogger.shared.log("🔐 [PrivCoordinator] VHID LaunchDaemon installed: \(hasService)")

        // Log current PIDs before any action (for diagnostics)
        let beforePIDs = Self.getDaemonPIDs()
        AppLogger.shared.log(
            "🔎 [PrivCoordinator] VHID PIDs before restart: \(beforePIDs.joined(separator: ", "))")

        // If present, boot it out to avoid KeepAlive race
        if hasService {
            let bootout = """
            /bin/launchctl bootout system/\(vhidLabel) 2>/dev/null || true
            /bin/launchctl disable system/\(vhidLabel) 2>/dev/null || true
            """
            do {
                try await sudoExecuteCommand(bootout, description: "Bootout VHID daemon service")
            } catch {
                AppLogger.shared.log("⚠️ [PrivCoordinator] Bootout returned error (continuing): \(error)")
            }
        }

        // Kill remaining processes (SIGTERM → SIGKILL)
        AppLogger.shared.log("🔐 [PrivCoordinator] Killing all VirtualHIDDevice daemon processes")
        let killCommand = """
        /usr/bin/pkill -f "Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
        /bin/sleep 0.3
        /usr/bin/pkill -9 -f "Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
        """
        do {
            try await sudoExecuteCommand(killCommand, description: "Kill VirtualHIDDevice daemons")
        } catch {
            AppLogger.shared.log(
                "⚠️ [PrivCoordinator] Kill failed (may be OK if no processes running): \(error)")
        }

        // Small settle
        try await Task.sleep(nanoseconds: 300_000_000)

        // Start via kickstart if service exists; otherwise start directly
        if hasService {
            AppLogger.shared.log("🔐 [PrivCoordinator] Starting VHID via launchctl kickstart")
            let kickstart = """
            /bin/launchctl enable system/\(vhidLabel) 2>/dev/null || true
            /bin/launchctl kickstart -k system/\(vhidLabel)
            """
            do {
                try await sudoExecuteCommand(kickstart, description: "Kickstart VHID daemon service")
            } catch {
                AppLogger.shared.log("❌ [PrivCoordinator] Kickstart failed: \(error)")
                return false
            }
        } else {
            AppLogger.shared.log(
                "🔐 [PrivCoordinator] LaunchDaemon missing - starting VHID by direct exec")
            let startCommand = """
            '\(daemonPath)' > /dev/null 2>&1 &
            """
            do {
                try await sudoExecuteCommand(startCommand, description: "Start VirtualHIDDevice daemon")
            } catch {
                AppLogger.shared.log("❌ [PrivCoordinator] Failed to start daemon: \(error)")
                return false
            }
        }

        // Log PIDs after kill, before start (for diagnostics)
        let afterKillPIDs = Self.getDaemonPIDs()
        AppLogger.shared.log(
            "🔎 [PrivCoordinator] VHID PIDs after kill: \(afterKillPIDs.joined(separator: ", "))")

        // Sustained verification: poll up to 3s for exactly one instance
        let vhidManager = VHIDDeviceManager()
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 3.0 {
            if await vhidManager.detectRunning() {
                AppLogger.shared.log(
                    "✅ [PrivCoordinator] Restart verified: daemon is healthy (single instance)")
                return true
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Final diagnostics
        let pids = Self.getDaemonPIDs()
        AppLogger.shared.log(
            "🔎 [PrivCoordinator] VHID PIDs after start: \(pids.joined(separator: ", "))")
        if pids.isEmpty {
            AppLogger.shared.log("❌ [PrivCoordinator] Verification failed: daemon not running")
        } else {
            AppLogger.shared.log(
                "❌ [PrivCoordinator] Verification failed: duplicates (\(pids.count)) PIDs=\(pids.joined(separator: ", "))"
            )
        }
        return false
    }

    /// Install bundled Kanata binary using KanataBinaryInstaller
    private func sudoInstallBundledKanata() async throws {
        let success = KanataBinaryInstaller.shared.installBundledKanata()

        if !success {
            throw PrivilegedOperationError.operationFailed("Bundled Kanata installation failed")
        }
    }

    /// Execute a shell command with administrator privileges using osascript
    /// Public method for use by KanataDaemonManager migration
    func sudoExecuteCommand(_ command: String, description: String) async throws {
        AppLogger.shared.log("🔧 [PrivCoordinator] Executing admin command: \(description)")
        let result = try await AdminCommandExecutorHolder.shared.execute(
            command: command, description: description
        )

        if result.exitCode == 0 {
            AppLogger.shared.log("✅ [PrivCoordinator] Successfully executed: \(description)")
        } else {
            AppLogger.shared.log("❌ [PrivCoordinator] Failed to execute: \(description)")
            AppLogger.shared.log("❌ [PrivCoordinator] Output: \(result.output)")
            throw PrivilegedOperationError.commandFailed(
                description: description,
                exitCode: result.exitCode,
                output: result.output
            )
        }
    }

    // MARK: - Helper Methods

    /// Escape a string for use in AppleScript
    private func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// Helper: current VHID daemon PIDs (best-effort, no throw)
    private static func getDaemonPIDs() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "Karabiner-VirtualHIDDevice-Daemon"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    private static func notifySMAppServiceApprovalRequired(context: String) {
        let now = Date()
        if let last = lastSMAppApprovalNotice,
           now.timeIntervalSince(last) < smAppApprovalNoticeThrottle
        {
            return
        }
        lastSMAppApprovalNotice = now
        AppLogger.shared.log(
            "⚠️ \(serviceGuardLogPrefix) \(context): SMAppService pending approval - notifying UI")
        NotificationCenter.default.post(name: .smAppServiceApprovalRequired, object: nil)
    }
}

#if DEBUG
    @_spi(ServiceInstallTesting)
    extension PrivilegedOperationsCoordinator {
        func _testEnsureServices(context: String) async throws -> Bool {
            try await installServicesIfUninstalled(context: context)
        }

        static func _testResetServiceInstallGuard() {
            serviceStateOverride = nil
            installAllServicesOverride = nil
            lastServiceInstallAttempt = nil
        }
    }
#endif

// MARK: - Error Types

enum PrivilegedOperationError: LocalizedError {
    case installationFailed(String)
    case operationFailed(String)
    case commandFailed(description: String, exitCode: Int32, output: String)
    case executionError(description: String, error: Error)

    var errorDescription: String? {
        switch self {
        case let .installationFailed(message):
            "Installation failed: \(message)"
        case let .operationFailed(message):
            "Operation failed: \(message)"
        case let .commandFailed(description, exitCode, output):
            "Command failed (\(description)): exit code \(exitCode)\nOutput: \(output)"
        case let .executionError(description, error):
            "Execution error (\(description)): \(error.localizedDescription)"
        }
    }
}
