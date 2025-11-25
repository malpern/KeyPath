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
        -> Bool {
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
           !override.isEmpty {
            return override
        }
        return "/bin/launchctl"
    }
}
