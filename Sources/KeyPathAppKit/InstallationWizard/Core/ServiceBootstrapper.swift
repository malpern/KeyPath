import Foundation
import KeyPathCore
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
                "🧪 [ServiceBootstrapper] Test mode - service \(serviceID) loaded: \(exists)")
            return exists
        }

        let launchctlPath = getLaunchctlPath()
        let plistPath = getPlistPath(for: serviceID)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchctlPath)
        task.arguments = ["load", "-w", plistPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [ServiceBootstrapper] Successfully loaded service: \(serviceID)")
                // Loading triggers program start; mark warm-up
                markRestartTime(for: [serviceID])
                return true
            } else {
                AppLogger.shared.log(
                    "❌ [ServiceBootstrapper] Failed to load service \(serviceID): \(output)")
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

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", plistPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [ServiceBootstrapper] Successfully unloaded service: \(serviceID)")
                return true
            } else {
                AppLogger.shared.log(
                    "⚠️ [ServiceBootstrapper] Service \(serviceID) may not have been loaded: \(output)")
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
    func restartServicesWithAdmin(_ serviceIDs: [String]) -> Bool {
        AppLogger.shared.log(
            "🔧 [ServiceBootstrapper] Restarting services with admin privileges: \(serviceIDs)")

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
        let commands = serviceIDs.map { "launchctl kickstart -k system/\($0)" }
            .joined(separator: " && ")

        AppLogger.shared.log("🔧 [ServiceBootstrapper] Executing admin command: \(commands)")

        // Use PrivilegedExecutor for admin operations
        let result = PrivilegedExecutor.shared.executeWithPrivileges(
            command: commands,
            prompt: "KeyPath needs to restart failing system services."
        )

        if result.success {
            AppLogger.shared.log(
                "✅ [ServiceBootstrapper] Successfully restarted services: \(serviceIDs)")
            // Mark warm-up start time for those services
            markRestartTime(for: serviceIDs)
        } else {
            AppLogger.shared.log(
                "❌ [ServiceBootstrapper] Failed to restart services: \(result.output)")
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

    // MARK: - Plist Installation

    /// Install a plist file to the system LaunchDaemons directory
    ///
    /// Writes the plist content to a temp file, then uses admin privileges to copy it to the final location.
    ///
    /// - Parameters:
    ///   - content: The plist XML content
    ///   - path: The destination path for the plist file
    ///   - serviceID: The service identifier (used for temp file naming)
    /// - Returns: `true` if installation succeeded
    func installPlist(content: String, path: String, serviceID: String) -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Installing plist: \(path)")

        // Skip admin operations in test environment
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log(
                "🧪 [TestEnvironment] Skipping plist installation - returning mock success")
            return true
        }

        // Create temporary file with plist content
        let tempDir = NSTemporaryDirectory()
        let tempPath = "\(tempDir)\(serviceID).plist"

        do {
            // Write content to temporary file first
            try content.write(toFile: tempPath, atomically: true, encoding: .utf8)

            // Use admin privileges to install the plist
            let success = installPlistWithPrivileges(tempPath: tempPath, finalPath: path, serviceID: serviceID)

            // Clean up temporary file
            try? FileManager.default.removeItem(atPath: tempPath)

            return success
        } catch {
            AppLogger.shared.log(
                "❌ [ServiceBootstrapper] Failed to create temporary plist \(serviceID): \(error)")
            return false
        }
    }

    /// Install plist using admin privileges
    private func installPlistWithPrivileges(tempPath: String, finalPath: String, serviceID: String) -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Installing plist with admin privileges: \(serviceID)")

        // Build the installation command
        let command = """
        mkdir -p '\((finalPath as NSString).deletingLastPathComponent)' && \
        cp '\(tempPath)' '\(finalPath)' && \
        chmod 644 '\(finalPath)' && \
        chown root:wheel '\(finalPath)'
        """

        let result = PrivilegedExecutor.shared.executeWithPrivileges(
            command: command,
            prompt: "KeyPath needs to install the \(serviceID) service."
        )

        if result.success {
            AppLogger.shared.log("✅ [ServiceBootstrapper] Plist installed: \(serviceID)")
        } else {
            AppLogger.shared.log("❌ [ServiceBootstrapper] Failed to install plist: \(result.output)")
        }

        return result.success
    }

    // MARK: - Log Rotation Service

    /// Install the log rotation service
    ///
    /// Creates the rotation script and plist, then installs them with admin privileges.
    ///
    /// - Returns: `true` if installation succeeded
    func installLogRotationService() async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Installing log rotation service (keeps logs < 10MB)")

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

            let result = PrivilegedExecutor.shared.executeWithPrivileges(
                command: command,
                prompt: "KeyPath needs to install the log rotation service."
            )

            // Clean up temp files
            try? FileManager.default.removeItem(atPath: scriptTempPath)
            try? FileManager.default.removeItem(atPath: plistTempPath)

            let success = result.success
            if success {
                AppLogger.shared.log("✅ [ServiceBootstrapper] Log rotation service installed successfully")
                rotateCurrentLogs()
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
    private func rotateCurrentLogs() {
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

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            AppLogger.shared.log("⚠️ [ServiceBootstrapper] Failed to rotate logs: \(error)")
        }
    }

    /// Check if log rotation service is installed
    func isLogRotationServiceInstalled() -> Bool {
        let plistPath = "\(getLaunchDaemonsPath())/\(Self.logRotationServiceID).plist"
        return FileManager.default.fileExists(atPath: plistPath)
    }

    // MARK: - VHID Service Repair

    /// Repair VHID daemon services
    ///
    /// Unloads, reinstalls, and reloads the VHID daemon and manager services.
    ///
    /// - Returns: `true` if repair succeeded
    func repairVHIDDaemonServices() async -> Bool {
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Repairing VHID LaunchDaemon services")

        // Unload services if present
        _ = await unloadService(serviceID: Self.vhidDaemonServiceID)
        _ = await unloadService(serviceID: Self.vhidManagerServiceID)

        // Reinstall plists with correct content
        let vhidDaemonPlist = PlistGenerator.generateVHIDDaemonPlist()
        let vhidManagerPlist = PlistGenerator.generateVHIDManagerPlist()
        let daemonPlistPath = "\(getLaunchDaemonsPath())/\(Self.vhidDaemonServiceID).plist"
        let managerPlistPath = "\(getLaunchDaemonsPath())/\(Self.vhidManagerServiceID).plist"

        let daemonInstall = installPlist(
            content: vhidDaemonPlist, path: daemonPlistPath, serviceID: Self.vhidDaemonServiceID
        )
        let managerInstall = installPlist(
            content: vhidManagerPlist, path: managerPlistPath, serviceID: Self.vhidManagerServiceID
        )

        guard daemonInstall, managerInstall else {
            AppLogger.shared.log("❌ [ServiceBootstrapper] Failed to install repaired VHID plists")
            return false
        }

        // Load services
        let daemonLoad = await loadService(serviceID: Self.vhidDaemonServiceID)
        let managerLoad = await loadService(serviceID: Self.vhidManagerServiceID)

        let ok = daemonLoad && managerLoad && ServiceHealthChecker.shared.isVHIDDaemonConfiguredCorrectly()
        AppLogger.shared.log(
            "🔍 [ServiceBootstrapper] Repair result: loadedDaemon=\(daemonLoad), loadedManager=\(managerLoad), configured=\(ServiceHealthChecker.shared.isVHIDDaemonConfiguredCorrectly())"
        )
        return ok
    }

    // MARK: - Service Installation (Install Only, No Load)

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

        // Install each plist
        let kanataOK = installPlist(content: kanataPlist, path: kanataPlistPath, serviceID: Self.kanataServiceID)
        let vhidDaemonOK = installPlist(content: vhidDaemonPlist, path: vhidDaemonPlistPath, serviceID: Self.vhidDaemonServiceID)
        let vhidManagerOK = installPlist(content: vhidManagerPlist, path: vhidManagerPlistPath, serviceID: Self.vhidManagerServiceID)

        let success = kanataOK && vhidDaemonOK && vhidManagerOK
        AppLogger.shared.log("🔧 [ServiceBootstrapper] Install-only result: kanata=\(kanataOK), vhidDaemon=\(vhidDaemonOK), vhidManager=\(vhidManagerOK)")
        return success
    }
}
