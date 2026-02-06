import Foundation
import KeyPathCore
import KeyPathWizardCore
import os.lock

/// Handles loading, unloading, and restarting of LaunchDaemon services.
///
/// This service provides a clean interface for managing macOS launchd services,
/// extracted from LaunchDaemonInstaller to support both LaunchDaemon and SMAppService paths.
///
/// ## Service Lifecycle Operations
/// - `loadService`: Load a service into launchd
/// - `unloadService`: Unload a service from launchd
/// - `loadServices`: Load multiple services
/// - `restartServicesWithAdmin`: Restart services with admin privileges
///
/// ## Restart Tracking
/// Tracks restart times to distinguish "starting" from "failed" states during warm-up period.
@MainActor
final class ServiceBootstrapper {
    static let shared = ServiceBootstrapper()

    private init() {}

    private(set) var lastVHIDRepairOutput: String?

    // MARK: - Service Identifiers

    /// Service identifier for the main Kanata keyboard remapping daemon
    static let kanataServiceID = "com.keypath.kanata"

    /// Service identifier for the Karabiner Virtual HID Device daemon
    static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"

    /// Service identifier for the Karabiner Virtual HID Device manager
    static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"

    /// Service identifier for the log rotation service
    static let logRotationServiceID = "com.keypath.logrotate"

    // MARK: - Restart Time Tracking

    /// Lock-protected dictionary tracking when services were last restarted
    private nonisolated static let restartTimeLock = OSAllocatedUnfairLock(initialState: [String: Date]())

    /// Default warm-up window (seconds) to distinguish "starting" from "failed"
    private nonisolated static let healthyWarmupWindow: TimeInterval = 2.0

    /// Mark that services were restarted at the current time
    /// Used to track warm-up period for health checks
    func markRestartTime(for serviceIDs: [String]) {
        let now = Date()
        Self.restartTimeLock.withLock { times in
            for id in serviceIDs {
                times[id] = now
            }
        }
    }

    /// Check if a service was recently restarted (within warm-up window)
    ///
    /// - Parameters:
    ///   - serviceID: The service identifier to check
    ///   - within: Time window in seconds (default: 2.0)
    /// - Returns: `true` if service was restarted within the window
    nonisolated static func wasRecentlyRestarted(
        _ serviceID: String, within seconds: TimeInterval? = nil
    ) -> Bool {
        let last = restartTimeLock.withLock { $0[serviceID] }
        guard let last else { return false }
        let window = seconds ?? healthyWarmupWindow
        return Date().timeIntervalSince(last) < window
    }

    /// Check if any service had a recent restart
    ///
    /// - Parameter within: Time window in seconds (default: 2.0)
    /// - Returns: `true` if any service was restarted within the window
    nonisolated static func hadRecentRestart(within seconds: TimeInterval = healthyWarmupWindow)
        -> Bool
    {
        let now = Date()
        return restartTimeLock.withLock { times in
            times.values.contains { now.timeIntervalSince($0) < seconds }
        }
    }

    // MARK: - Service Loading

    /// Load a specific LaunchDaemon service into launchd
    ///
    /// - Parameter serviceID: The service identifier (e.g., "com.keypath.kanata")
    /// - Returns: `true` if the service was loaded successfully
    func loadService(serviceID: String) async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Loading service: \(serviceID)")

        // Test mode: just check if plist exists
        if TestEnvironment.shouldSkipAdminOperations {
            let plistPath = getPlistPath(for: serviceID)
            let exists = FileManager.default.fileExists(atPath: plistPath)
            AppLogger.shared.log(
                "🧪 [ServiceBootstrapper] Test mode - service \(serviceID) loaded: \(exists)"
            )
            return exists
        }

        let launchctlPath = getLaunchctlPath()
        let plistPath = getPlistPath(for: serviceID)

        do {
            let result = try await SubprocessRunner.shared.run(
                launchctlPath,
                args: ["load", "-w", plistPath],
                timeout: 10
            )

            if result.exitCode == 0 {
                AppLogger.shared.log("✅ [ServiceBootstrapper] Successfully loaded service: \(serviceID)")
                // Loading triggers program start; mark warm-up
                markRestartTime(for: [serviceID])
                return true
            } else {
                AppLogger.shared.log(
                    "❌ [ServiceBootstrapper] Failed to load service \(serviceID): \(result.stderr)"
                )
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [ServiceBootstrapper] Error loading service \(serviceID): \(error)")
            return false
        }
    }

    /// Load multiple LaunchDaemon services
    ///
    /// - Parameter serviceIDs: Array of service identifiers to load
    /// - Returns: `true` if all services were loaded successfully
    func loadServices(_ serviceIDs: [String]) async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Loading \(serviceIDs.count) services")

        var allSucceeded = true

        for serviceID in serviceIDs {
            let success = await loadService(serviceID: serviceID)
            if !success {
                allSucceeded = false
                AppLogger.shared.log("❌ [ServiceBootstrapper] Failed to load service: \(serviceID)")
            }
        }

        return allSucceeded
    }

    // MARK: - Service Unloading

    /// Unload a specific LaunchDaemon service from launchd
    ///
    /// - Parameter serviceID: The service identifier to unload
    /// - Returns: `true` if the service was unloaded successfully (or wasn't loaded)
    func unloadService(serviceID: String) async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Unloading service: \(serviceID)")

        // Test mode: always succeed
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [ServiceBootstrapper] Test mode - simulating unload success")
            return true
        }

        let plistPath = getPlistPath(for: serviceID)

        do {
            let result = try await SubprocessRunner.shared.launchctl("unload", [plistPath])

            if result.exitCode == 0 {
                AppLogger.shared.log("✅ [ServiceBootstrapper] Successfully unloaded service: \(serviceID)")
                return true
            } else {
                AppLogger.shared.log(
                    "⚠️ [ServiceBootstrapper] Service \(serviceID) may not have been loaded: \(result.stderr)"
                )
                // Not an error if it wasn't loaded
                return true
            }
        } catch {
            AppLogger.shared.log("❌ [ServiceBootstrapper] Error unloading service \(serviceID): \(error)")
            return false
        }
    }

    // MARK: - Service Restart

    /// Restart services with administrator privileges using launchctl kickstart
    ///
    /// This uses `launchctl kickstart -k` which forcefully restarts services.
    /// Requires admin privileges to restart system services.
    ///
    /// - Parameter serviceIDs: Array of service identifiers to restart
    /// - Returns: `true` if all services were restarted successfully
    func restartServicesWithAdmin(_ serviceIDs: [String]) async -> Bool {
        AppLogger.shared.log(
            "🔧 [ServiceBootstrapper] Restarting services with admin privileges: \(serviceIDs)"
        )

        // Test mode: simulate success
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [ServiceBootstrapper] Test mode - simulating successful restart")
            markRestartTime(for: serviceIDs)
            return true
        }

        guard !serviceIDs.isEmpty else {
            AppLogger.shared.log("🔧 [ServiceBootstrapper] No services to restart - returning success")
            return true
        }

        // Build kickstart commands for all services
        let commands = serviceIDs.map { "/bin/launchctl kickstart -k system/\($0)" }
        let result = await executePrivilegedBatch(
            label: "restart failing system services",
            commands: commands,
            prompt: "KeyPath needs to restart failing system services."
        )

        if result.success {
            AppLogger.shared.log(
                "✅ [ServiceBootstrapper] Successfully restarted services: \(serviceIDs)"
            )
            // Mark warm-up start time for those services
            markRestartTime(for: serviceIDs)
        } else {
            AppLogger.shared.log(
                "❌ [ServiceBootstrapper] Failed to restart services: \(result.output)"
            )
        }

        return result.success
    }

    // MARK: - Helper Methods

    /// Get the plist file path for a service
    ///
    /// - Parameter serviceID: The service identifier
    /// - Returns: Full path to the service plist file
    private func getPlistPath(for serviceID: String) -> String {
        let launchDaemonsPath = getLaunchDaemonsPath()
        return "\(launchDaemonsPath)/\(serviceID).plist"
    }

    /// Get the launchd daemons directory path
    ///
    /// - Returns: Path to /Library/LaunchDaemons (or test override)
    private func getLaunchDaemonsPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let override = env["KEYPATH_LAUNCH_DAEMONS_DIR"], !override.isEmpty {
            return override
        }
        return WizardSystemPaths.remapSystemPath("/Library/LaunchDaemons")
    }

    /// Get the launchctl executable path
    ///
    /// - Returns: Path to launchctl (or test override)
    private func getLaunchctlPath() -> String {
        // Allow override for testing
        if let override = ProcessInfo.processInfo.environment["KEYPATH_LAUNCHCTL_PATH"],
           !override.isEmpty
        {
            return override
        }
        return "/bin/launchctl"
    }

    // MARK: - Privileged Helpers

    private struct PlistInstallSpec {
        let content: String
        let path: String
        let serviceID: String
    }

    private func preparePlistInstall(
        specs: [PlistInstallSpec]
    ) throws -> (tempFiles: [String], commands: [String]) {
        let tempDir = NSTemporaryDirectory()
        var tempFiles: [String] = []
        var commands: [String] = []

        let parentDirs = Set(specs.map { ($0.path as NSString).deletingLastPathComponent })
        for dir in parentDirs.sorted() {
            commands.append("mkdir -p '\(dir)'")
        }

        for spec in specs {
            let tempPath = "\(tempDir)\(spec.serviceID)_\(UUID().uuidString).plist"
            try spec.content.write(toFile: tempPath, atomically: true, encoding: .utf8)
            tempFiles.append(tempPath)

            commands.append("cp '\(tempPath)' '\(spec.path)'")
            commands.append("chmod 644 '\(spec.path)'")
            commands.append("chown root:wheel '\(spec.path)'")
        }

        return (tempFiles, commands)
    }

    private func executePrivilegedBatch(
        label: String,
        commands: [String],
        prompt: String
    ) async -> (success: Bool, output: String) {
        let batch = PrivilegedCommandRunner.Batch(label: label, commands: commands, prompt: prompt)
        do {
            let result = try await AdminCommandExecutorHolder.shared.execute(batch: batch)
            return (result.exitCode == 0, result.output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Log Rotation Service

    /// Install the log rotation service
    ///
    /// Creates the rotation script and plist, then installs them with admin privileges.
    ///
    /// - Returns: `true` if installation succeeded
    func installLogRotationService() async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Installing log rotation service (keeps logs < 10MB)")

        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [ServiceBootstrapper] Test mode - skipping log rotation install")
            return true
        }

        let script = generateLogRotationScript()
        let plist = PlistGenerator.generateLogRotationPlist(scriptPath: logRotationScriptPath)

        let tempDir = NSTemporaryDirectory()
        let scriptTempPath = "\(tempDir)keypath-logrotate.sh"
        let plistTempPath = "\(tempDir)\(Self.logRotationServiceID).plist"

        do {
            // Write script and plist to temp files
            try script.write(toFile: scriptTempPath, atomically: true, encoding: .utf8)
            try plist.write(toFile: plistTempPath, atomically: true, encoding: .utf8)

            // Install both with admin privileges
            let scriptFinal = logRotationScriptPath
            let plistFinal = "\(getLaunchDaemonsPath())/\(Self.logRotationServiceID).plist"

            let command = """
            mkdir -p /usr/local/bin && \
            cp '\(scriptTempPath)' '\(scriptFinal)' && \
            chmod 755 '\(scriptFinal)' && \
            chown root:wheel '\(scriptFinal)' && \
            cp '\(plistTempPath)' '\(plistFinal)' && \
            chmod 644 '\(plistFinal)' && \
            chown root:wheel '\(plistFinal)' && \
            launchctl bootstrap system '\(plistFinal)'
            """

            let result = await executePrivilegedBatch(
                label: "install log rotation service",
                commands: [command],
                prompt: "KeyPath needs to install the log rotation service."
            )

            // Clean up temp files
            try? FileManager.default.removeItem(atPath: scriptTempPath)
            try? FileManager.default.removeItem(atPath: plistTempPath)

            let success = result.success
            if success {
                AppLogger.shared.log("✅ [ServiceBootstrapper] Log rotation service installed successfully")
                await rotateCurrentLogs()
            } else {
                AppLogger.shared.log("❌ [ServiceBootstrapper] Failed to install log rotation service: \(result.output)")
            }

            return success

        } catch {
            AppLogger.shared.log("❌ [ServiceBootstrapper] Error preparing log rotation files: \(error)")
            return false
        }
    }

    /// Path to the log rotation script
    private var logRotationScriptPath: String {
        "/usr/local/bin/keypath-logrotate.sh"
    }

    /// Generate the log rotation shell script
    private func generateLogRotationScript() -> String {
        """
        #!/bin/bash
        # KeyPath Log Rotation Script - keeps logs under 10MB
        LOG_FILE="/var/log/kanata.log"
        MAX_SIZE=$((10 * 1024 * 1024))  # 10MB

        if [[ -f "$LOG_FILE" ]]; then
            size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
            if [[ $size -gt $MAX_SIZE ]]; then
                # Rotate logs: remove old backup, move current to .1
                [[ -f "${LOG_FILE}.1" ]] && rm -f "${LOG_FILE}.1"
                mv "$LOG_FILE" "${LOG_FILE}.1"
                touch "$LOG_FILE"
                chmod 644 "$LOG_FILE"
                echo "$(date): Rotated kanata.log ($size bytes)" >> /var/log/keypath-rotation.log
            fi
        fi
        """
    }

    /// Immediately rotate current large log files
    private func rotateCurrentLogs() async {
        AppLogger.shared.log("🔄 [ServiceBootstrapper] Immediately rotating current large log files")

        let command = """
        [[ -f /var/log/kanata.log ]] && \
        size=$(stat -f%z /var/log/kanata.log 2>/dev/null || echo 0) && \
        if [[ $size -gt 5242880 ]]; then \
            echo "Rotating kanata.log ($size bytes)"; \
            [[ -f /var/log/kanata.log.1 ]] && rm -f /var/log/kanata.log.1; \
            mv /var/log/kanata.log /var/log/kanata.log.1; \
            touch /var/log/kanata.log && chmod 644 /var/log/kanata.log; \
        fi
        """

        do {
            _ = try await SubprocessRunner.shared.run(
                "/bin/sh",
                args: ["-c", command],
                timeout: 5
            )
        } catch {
            AppLogger.shared.log("⚠️ [ServiceBootstrapper] Failed to rotate logs: \(error)")
        }
    }

    /// Check if log rotation service is installed
    func isLogRotationServiceInstalled() -> Bool {
        let plistPath = "\(getLaunchDaemonsPath())/\(Self.logRotationServiceID).plist"
        return FileManager.default.fileExists(atPath: plistPath)
    }

    // MARK: - Restart Unhealthy Services

    /// Restart unhealthy services and diagnose/fix underlying issues
    ///
    /// This comprehensive health fix handles:
    /// - Service status categorization (restart vs install)
    /// - SMAppService state management and conflict resolution
    /// - SMAppService broken state handling with retry logic
    /// - Conditional installation and restart
    ///
    /// - Returns: `true` if all services are healthy after the operation
    @MainActor
    func restartUnhealthyServices() async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Starting comprehensive service health fix")

        // Skip in test mode
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [ServiceBootstrapper] Test mode - simulating successful restart")
            return true
        }

        // Get initial service status
        let initialStatus = await ServiceHealthChecker.shared.getServiceStatus()
        var toRestart: [String] = []
        var toInstall: [String] = []

        // Categorize services by what they need
        if initialStatus.kanataServiceLoaded, !initialStatus.kanataServiceHealthy {
            toRestart.append(Self.kanataServiceID)
        } else if !initialStatus.kanataServiceLoaded {
            toInstall.append(Self.kanataServiceID)
        }

        if initialStatus.vhidDaemonServiceLoaded, !initialStatus.vhidDaemonServiceHealthy {
            toRestart.append(Self.vhidDaemonServiceID)
        } else if !initialStatus.vhidDaemonServiceLoaded {
            toInstall.append(Self.vhidDaemonServiceID)
        }

        if initialStatus.vhidManagerServiceLoaded, !initialStatus.vhidManagerServiceHealthy {
            toRestart.append(Self.vhidManagerServiceID)
        } else if !initialStatus.vhidManagerServiceLoaded {
            toInstall.append(Self.vhidManagerServiceID)
        }

        // Check SMAppService state
        let state = await KanataDaemonManager.shared.refreshManagementState()
        AppLogger.shared.log("🔍 [ServiceBootstrapper] SMAppService state: \(state.description)")

        // Auto-resolve legacy/conflicted state
        if state == .legacyActive || state == .conflicted {
            await resolveLegacyConflict()
        }

        // Handle SMAppService broken state (common after clean uninstall)
        let isRegisteredButBroken = await KanataDaemonManager.shared.isRegisteredButNotLoaded()
        if isRegisteredButBroken {
            await fixBrokenSMAppServiceState()
        }

        // Filter out Kanata from installation if SMAppService is managing it
        if toInstall.contains(Self.kanataServiceID) {
            if state.isSMAppServiceManaged {
                AppLogger.shared.log("⚠️ [ServiceBootstrapper] Kanata managed by SMAppService - skipping install")
                toInstall.removeAll { $0 == Self.kanataServiceID }
            } else if state == .unknown {
                let health = await ServiceHealthChecker.shared.checkKanataServiceHealth()
                if health.isRunning {
                    AppLogger.shared.log("⚠️ [ServiceBootstrapper] Unknown state but running - skipping install")
                    toInstall.removeAll { $0 == Self.kanataServiceID }
                }
            }
        }

        // Step 1: Install missing services if needed
        if !toInstall.isEmpty {
            AppLogger.shared.log("🔧 [ServiceBootstrapper] Installing missing services: \(toInstall)")
            let installSuccess = await installAllServices()
            if !installSuccess {
                AppLogger.shared.log("❌ [ServiceBootstrapper] Failed to install services")
                return false
            }
            // Wait for installation to settle
            // Poll for launchctl to report loaded within warm-up window
            for _ in 0 ..< 10 { // ~2s with 200ms steps
                if await ServiceHealthChecker.shared.isServiceLoaded(serviceID: Self.kanataServiceID) {
                    break
                }
                _ = await WizardSleep.ms(200) // 200ms poll interval
            }
        }

        // Step 2: Handle unhealthy services
        if toRestart.isEmpty {
            AppLogger.shared.log("✅ [ServiceBootstrapper] No unhealthy services to restart")
            return true
        }

        // Handle Kanata via SMAppService refresh (no admin prompt needed)
        if toRestart.contains(Self.kanataServiceID), state.isSMAppServiceManaged {
            AppLogger.shared.log("🔧 [ServiceBootstrapper] Refreshing Kanata via SMAppService")
            do {
                try await KanataDaemonManager.shared.unregister()
                // Poll for service readiness with a short wait, instead of fixed sleep
                for _ in 0 ..< 6 { // ~0.6s
                    if await ServiceHealthChecker.shared.isServiceHealthy(serviceID: Self.kanataServiceID) {
                        break
                    }
                    _ = await WizardSleep.ms(100)
                }
                try await KanataDaemonManager.shared.register()
                toRestart.removeAll { $0 == Self.kanataServiceID }
                AppLogger.shared.log("✅ [ServiceBootstrapper] Kanata SMAppService refreshed")
            } catch {
                AppLogger.shared.log("⚠️ [ServiceBootstrapper] SMAppService refresh failed: \(error)")
            }
        }

        // Restart remaining unhealthy services
        if !toRestart.isEmpty {
            AppLogger.shared.log("🔧 [ServiceBootstrapper] Restarting services: \(toRestart)")
            let restartSuccess = await restartServicesWithAdmin(toRestart)
            if !restartSuccess {
                AppLogger.shared.log("❌ [ServiceBootstrapper] Failed to restart services")
                return false
            }
        }

        AppLogger.shared.log("✅ [ServiceBootstrapper] Service health fix complete")
        return true
    }

    /// Resolve legacy/conflicted SMAppService state
    @MainActor
    private func resolveLegacyConflict() async {
        AppLogger.shared.log("🔄 [ServiceBootstrapper] Resolving legacy/conflicted state")
        let legacyPlistPath = KanataDaemonManager.legacyPlistPath
        let command = """
        /bin/launchctl bootout system/\(Self.kanataServiceID) 2>/dev/null || true && \
        /bin/rm -f '\(legacyPlistPath)' || true
        """
        let result = await executePrivilegedBatch(
            label: "remove legacy service configuration",
            commands: [command],
            prompt: "KeyPath needs to remove the legacy service configuration."
        )
        if result.success {
            AppLogger.shared.log("✅ [ServiceBootstrapper] Legacy conflict resolved")
        } else {
            AppLogger.shared.log("⚠️ [ServiceBootstrapper] Failed to resolve conflict: \(result.output)")
        }
    }

    /// Fix broken SMAppService state with retry logic
    @MainActor
    private func fixBrokenSMAppServiceState() async {
        AppLogger.shared.log("🔄 [ServiceBootstrapper] Fixing broken SMAppService state")
        AppLogger.shared.log("🐛 Known macOS bug: BundleProgram path caching after uninstall/reinstall")

        let maxRetries = 2
        for attempt in 1 ... maxRetries {
            do {
                AppLogger.shared.log("🔄 Attempt \(attempt)/\(maxRetries)")

                try await KanataDaemonManager.shared.unregister()
                for _ in 0 ..< 10 { // ~1s
                    if await ServiceHealthChecker.shared.isServiceHealthy(serviceID: Self.kanataServiceID) {
                        break
                    }
                    _ = await WizardSleep.ms(100)
                }
                try await KanataDaemonManager.shared.register()
                for _ in 0 ..< 20 { // ~2s
                    if await ServiceHealthChecker.shared.isServiceHealthy(serviceID: Self.kanataServiceID) {
                        break
                    }
                    _ = await WizardSleep.ms(100)
                }

                let stillBroken = await KanataDaemonManager.shared.isRegisteredButNotLoaded()
                if !stillBroken {
                    AppLogger.shared.log("✅ [ServiceBootstrapper] Fixed SMAppService broken state")
                    return
                }
            } catch {
                AppLogger.shared.log("❌ Attempt \(attempt) failed: \(error)")
            }
            for _ in 0 ..< 5 {
                if await ServiceHealthChecker.shared.isServiceHealthy(serviceID: Self.kanataServiceID) {
                    break
                }
                _ = await WizardSleep.ms(100)
            }
        }
        AppLogger.shared.log("⚠️ [ServiceBootstrapper] Could not fix SMAppService state - user may need to reboot")
    }

    // MARK: - VHID Service Repair

    /// Repair VHID daemon services
    ///
    /// Unloads, reinstalls, and reloads the VHID daemon and manager services.
    ///
    /// - Returns: `true` if repair succeeded
    func repairVHIDDaemonServices() async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Repairing VHID LaunchDaemon services")

        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [ServiceBootstrapper] Test mode - skipping VHID repair")
            lastVHIDRepairOutput = "Skipped in test mode"
            return true
        }

        // Reinstall plists with correct content
        let vhidDaemonPlist = PlistGenerator.generateVHIDDaemonPlist()
        let vhidManagerPlist = PlistGenerator.generateVHIDManagerPlist()
        let daemonPlistPath = "\(getLaunchDaemonsPath())/\(Self.vhidDaemonServiceID).plist"
        let managerPlistPath = "\(getLaunchDaemonsPath())/\(Self.vhidManagerServiceID).plist"

        let plistSpecs = [
            PlistInstallSpec(
                content: vhidDaemonPlist,
                path: daemonPlistPath,
                serviceID: Self.vhidDaemonServiceID
            ),
            PlistInstallSpec(
                content: vhidManagerPlist,
                path: managerPlistPath,
                serviceID: Self.vhidManagerServiceID
            )
        ]

        let preflightIssues = await VHIDDeviceManager().securityPreflightIssues()
        if !preflightIssues.isEmpty {
            AppLogger.shared.log(
                "⚠️ [ServiceBootstrapper] VHID preflight security issues detected:\n- \(preflightIssues.joined(separator: "\n- "))"
            )
        }

        let prepared: (tempFiles: [String], commands: [String])
        do {
            prepared = try preparePlistInstall(specs: plistSpecs)
        } catch {
            AppLogger.shared.log(
                "❌ [ServiceBootstrapper] Failed to prepare VHID plists: \(error)"
            )
            lastVHIDRepairOutput = "Failed to prepare VHID plists: \(error.localizedDescription)"
            return false
        }

        defer {
            for tempFile in prepared.tempFiles {
                try? FileManager.default.removeItem(atPath: tempFile)
            }
        }

        var privilegedCommands = prepared.commands
        privilegedCommands.append(contentsOf: [
            "/bin/launchctl bootout system/\(Self.vhidDaemonServiceID) 2>/dev/null || true",
            "/bin/launchctl bootout system/\(Self.vhidManagerServiceID) 2>/dev/null || true",
            "/usr/bin/xattr -d com.apple.quarantine '\(VHIDDeviceManager.vhidManagerPath)' 2>/dev/null || true",
            "/usr/bin/xattr -d com.apple.quarantine '\(VHIDDeviceManager.vhidDeviceDaemonPath)' 2>/dev/null || true",
            "/bin/launchctl bootstrap system '\(daemonPlistPath)'",
            "/bin/launchctl bootstrap system '\(managerPlistPath)'",
            "/bin/launchctl enable system/\(Self.vhidDaemonServiceID)",
            "/bin/launchctl enable system/\(Self.vhidManagerServiceID)",
            "/bin/launchctl kickstart -k system/\(Self.vhidDaemonServiceID)",
            "/bin/launchctl kickstart -k system/\(Self.vhidManagerServiceID)"
        ])

        let batchResult = await executePrivilegedBatch(
            label: "repair VirtualHID services",
            commands: privilegedCommands,
            prompt: "KeyPath needs to repair the VirtualHID services."
        )
        if batchResult.success {
            AppLogger.shared.log("✅ [ServiceBootstrapper] VHID repair batch succeeded")
        } else {
            AppLogger.shared.log(
                "❌ [ServiceBootstrapper] VHID repair batch failed: \(batchResult.output)"
            )
        }

        let daemonLoaded = await ServiceHealthChecker.shared.isServiceLoaded(serviceID: Self.vhidDaemonServiceID)
        let managerLoaded = await ServiceHealthChecker.shared.isServiceLoaded(serviceID: Self.vhidManagerServiceID)
        let configured = ServiceHealthChecker.shared.isVHIDDaemonConfiguredCorrectly()
        let postflightIssues = await VHIDDeviceManager().securityPreflightIssues()
        let ok = batchResult.success && daemonLoaded && managerLoaded && configured
        lastVHIDRepairOutput = formatVHIDRepairOutput(
            bootstrapOutput: batchResult.output,
            daemonLoaded: daemonLoaded,
            managerLoaded: managerLoaded,
            configured: configured,
            securityIssues: postflightIssues
        )
        AppLogger.shared.log(
            "🔍 [ServiceBootstrapper] Repair result: bootstrapOK=\(batchResult.success), loadedDaemon=\(daemonLoaded), loadedManager=\(managerLoaded), configured=\(configured)"
        )
        return ok
    }

    private func formatVHIDRepairOutput(
        bootstrapOutput: String,
        daemonLoaded: Bool,
        managerLoaded: Bool,
        configured: Bool,
        securityIssues: [String]
    ) -> String? {
        var details: [String] = []
        let trimmed = bootstrapOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            details.append(trimmed)
        }
        if !daemonLoaded {
            details.append("Service not loaded: \(Self.vhidDaemonServiceID)")
        }
        if !managerLoaded {
            details.append("Service not loaded: \(Self.vhidManagerServiceID)")
        }
        if !configured {
            details.append("VHID daemon plist configuration check failed")
        }
        if !securityIssues.isEmpty {
            details.append("Security checks:")
            details.append(contentsOf: securityIssues.map { "- \($0)" })
        }
        return details.isEmpty ? nil : details.joined(separator: "\n")
    }

    // MARK: - Service Installation (Install Only, No Load)

    // MARK: - Full Service Installation (SMAppService + VHID)

    /// Install all services: VirtualHID via launchctl, Kanata via SMAppService
    ///
    /// This is the primary installation method that combines:
    /// 1. VirtualHID services installation via launchctl
    /// 2. Kanata daemon registration via SMAppService
    ///
    /// - Returns: `true` if all services were installed successfully
    @MainActor
    func installAllServices() async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Installing all services (VHID + Kanata)")

        // Skip in test mode
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [ServiceBootstrapper] Test mode - simulating successful installation")
            return true
        }

        // Step 1: Install VirtualHID services (helper-first, falls back to osascript)
        AppLogger.shared.log("📱 [ServiceBootstrapper] Step 1: Installing VirtualHID services via InstallerEngine")
        let report = await InstallerEngine()
            .runSingleAction(.repairVHIDDaemonServices, using: PrivilegeBroker())
        if !report.success {
            AppLogger.shared.log(
                "❌ [ServiceBootstrapper] VirtualHID installation failed: \(report.failureReason ?? "Unknown error")"
            )
            return false
        }

        // Step 2: Install Kanata via SMAppService
        AppLogger.shared.log("📱 [ServiceBootstrapper] Step 2: Installing Kanata via SMAppService")
        let kanataSuccess = await registerKanataWithSMAppService()

        if !kanataSuccess {
            AppLogger.shared.log("⚠️ [ServiceBootstrapper] SMAppService registration failed")
            AppLogger.shared.log("💡 [ServiceBootstrapper] User may need to approve in System Settings")
            return false
        }

        AppLogger.shared.info("✅ [ServiceBootstrapper] All services installed successfully")
        return true
    }

    /// Register Kanata daemon via SMAppService
    ///
    /// Handles state checking, conflict resolution, and SMAppService registration.
    ///
    /// - Returns: `true` if registration succeeded or already registered
    @MainActor
    private func registerKanataWithSMAppService() async -> Bool {
        AppLogger.shared.log("📱 [ServiceBootstrapper] Registering Kanata daemon via SMAppService")

        guard #available(macOS 13, *) else {
            AppLogger.shared.log("❌ [ServiceBootstrapper] SMAppService requires macOS 13+")
            return false
        }

        // Check current state
        let state = await KanataDaemonManager.shared.refreshManagementState()
        AppLogger.shared.log("🔍 [ServiceBootstrapper] Current state: \(state.description)")

        // If conflicted, auto-resolve by removing legacy plist
        if state == .conflicted {
            AppLogger.shared.log("⚠️ [ServiceBootstrapper] Conflicted state - auto-resolving by removing legacy")
            let legacyPlistPath = KanataDaemonManager.legacyPlistPath
            let command = """
            /bin/launchctl bootout system/\(Self.kanataServiceID) 2>/dev/null || true && \
            /bin/rm -f '\(legacyPlistPath)' || true
            """
            let result = await executePrivilegedBatch(
                label: "remove legacy service configuration",
                commands: [command],
                prompt: "KeyPath needs to remove the legacy service configuration."
            )
            if !result.success {
                AppLogger.shared.log("❌ [ServiceBootstrapper] Failed to resolve conflict: \(result.output)")
                return false
            }
            AppLogger.shared.log("✅ [ServiceBootstrapper] Legacy plist removed, conflict resolved")
        }

        // If already managed by SMAppService, skip registration
        if state.isSMAppServiceManaged {
            AppLogger.shared.log("✅ [ServiceBootstrapper] Already managed by SMAppService - skipping")
            return true
        }

        // Register with SMAppService
        do {
            AppLogger.shared.log("🔧 [ServiceBootstrapper] Calling KanataDaemonManager.register()...")
            try await KanataDaemonManager.shared.register()
            AppLogger.shared.info("✅ [ServiceBootstrapper] Kanata daemon registered via SMAppService")
            return true
        } catch {
            AppLogger.shared.log("❌ [ServiceBootstrapper] SMAppService registration failed: \(error)")
            return false
        }
    }

    /// Install all LaunchDaemon service plists without loading them
    ///
    /// Used for adopting orphan processes where we want the plist in place
    /// but don't want to load services yet.
    ///
    /// - Parameter binaryPath: Path to the Kanata binary
    /// - Returns: `true` if all plists were installed successfully
    func installAllServicesWithoutLoading(binaryPath: String) async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Installing service plists (no loading)")

        // Skip admin operations in test environment
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [TestEnvironment] Skipping service installation - returning mock success")
            return true
        }

        // Generate plists
        let kanataPlist = PlistGenerator.generateKanataPlist(
            binaryPath: binaryPath,
            configPath: WizardSystemPaths.userConfigPath,
            tcpPort: 37001
        )
        let vhidDaemonPlist = PlistGenerator.generateVHIDDaemonPlist()
        let vhidManagerPlist = PlistGenerator.generateVHIDManagerPlist()

        let launchDaemonsDir = getLaunchDaemonsPath()
        let kanataPlistPath = "\(launchDaemonsDir)/\(Self.kanataServiceID).plist"
        let vhidDaemonPlistPath = "\(launchDaemonsDir)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerPlistPath = "\(launchDaemonsDir)/\(Self.vhidManagerServiceID).plist"

        let specs = [
            PlistInstallSpec(
                content: kanataPlist,
                path: kanataPlistPath,
                serviceID: Self.kanataServiceID
            ),
            PlistInstallSpec(
                content: vhidDaemonPlist,
                path: vhidDaemonPlistPath,
                serviceID: Self.vhidDaemonServiceID
            ),
            PlistInstallSpec(
                content: vhidManagerPlist,
                path: vhidManagerPlistPath,
                serviceID: Self.vhidManagerServiceID
            )
        ]

        let prepared: (tempFiles: [String], commands: [String])
        do {
            prepared = try preparePlistInstall(specs: specs)
        } catch {
            AppLogger.shared.log("❌ [ServiceBootstrapper] Failed to prepare service plists: \(error)")
            return false
        }

        defer {
            for tempFile in prepared.tempFiles {
                try? FileManager.default.removeItem(atPath: tempFile)
            }
        }

        let result = await executePrivilegedBatch(
            label: "install service plists",
            commands: prepared.commands,
            prompt: "KeyPath needs to install the service plists."
        )
        AppLogger.shared.log(
            "🔧 [ServiceBootstrapper] Install-only result: success=\(result.success)"
        )
        return result.success
    }
}
