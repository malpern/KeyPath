import Foundation

/// Manages the Karabiner VirtualHIDDevice Manager component
/// This is critical for keyboard remapping functionality on macOS
class VHIDDeviceManager {
    // MARK: - Constants

    private static let vhidManagerPath =
        "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    private static let vhidManagerBundleID = "org.pqrs.Karabiner-VirtualHIDDevice-Manager"
    private static let vhidDeviceDaemonPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    private static let vhidDeviceRunningCheck = "Karabiner-VirtualHIDDevice-Daemon"

    // MARK: - Detection Methods

    /// Checks if the VirtualHIDDevice Manager application is installed
    func detectInstallation() -> Bool {
        let fileManager = FileManager.default
        let appExists = fileManager.fileExists(atPath: Self.vhidManagerPath)

        AppLogger.shared.log(
            "🔍 [VHIDManager] Manager app exists at \(Self.vhidManagerPath): \(appExists)")
        return appExists
    }

    /// Checks if the VirtualHIDDevice Manager has been activated
    /// This involves checking if the daemon binaries are in place
    func detectActivation() -> Bool {
        let fileManager = FileManager.default
        let daemonExists = fileManager.fileExists(atPath: Self.vhidDeviceDaemonPath)

        AppLogger.shared.log(
            "🔍 [VHIDManager] Daemon exists at \(Self.vhidDeviceDaemonPath): \(daemonExists)")
        return daemonExists
    }

    /// Checks if VirtualHIDDevice processes are currently running
    func detectRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", Self.vhidDeviceRunningCheck]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let isRunning =
                task.terminationStatus == 0
                    && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            AppLogger.shared.log("🔍 [VHIDManager] VHIDDevice processes running: \(isRunning)")
            return isRunning
        } catch {
            AppLogger.shared.log("❌ [VHIDManager] Error checking VHIDDevice processes: \(error)")
            return false
        }
    }

    /// Checks if VirtualHID daemon is functioning correctly (not just running)
    /// This includes checking for connection errors in Kanata logs
    func detectConnectionHealth() -> Bool {
        // First check if daemon is running
        guard detectRunning() else {
            AppLogger.shared.log("🔍 [VHIDManager] Daemon not running - connection health: false")
            return false
        }

        // Use fast tail approach instead of reading entire file
        let logPath = "/var/log/kanata.log"
        guard FileManager.default.fileExists(atPath: logPath) else {
            AppLogger.shared.log("🔍 [VHIDManager] No Kanata log file - assuming connection healthy")
            return true
        }

        do {
            // Use tail command for fast log reading (last 50 lines only)
            let task = Process()
            task.launchPath = "/usr/bin/tail"
            task.arguments = ["-50", logPath]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            // Add timeout to prevent hanging
            task.launch()
            
            // Wait with timeout (1 second max)
            let group = DispatchGroup()
            group.enter()
            
            DispatchQueue.global().async {
                task.waitUntilExit()
                group.leave()
            }
            
            let result = group.wait(timeout: .now() + 1.0)
            if result == .timedOut {
                task.terminate()
                AppLogger.shared.log("⚠️ [VHIDManager] Log check timed out - assuming healthy")
                return true
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let logContent = String(data: data, encoding: .utf8) ?? ""
            let recentLines = logContent.components(separatedBy: .newlines)

            let connectionFailures = recentLines.filter { line in
                line.contains("connect_failed asio.system:2")
                    || line.contains("connect_failed asio.system:61")
            }

            let successfulConnections = recentLines.filter { line in
                line.contains("driver_connected 1")
            }

            // If we see recent connection failures without recent successes, consider unhealthy
            let hasRecentFailures = connectionFailures.count > 5
            let hasRecentSuccess = !successfulConnections.isEmpty

            let isHealthy = !hasRecentFailures || hasRecentSuccess

            AppLogger.shared.log("🔍 [VHIDManager] Connection health check:")
            AppLogger.shared.log("  - Recent failures: \(connectionFailures.count)")
            AppLogger.shared.log("  - Recent successes: \(successfulConnections.count)")
            AppLogger.shared.log("  - Health status: \(isHealthy)")

            return isHealthy
        } catch {
            AppLogger.shared.log("⚠️ [VHIDManager] Error reading log file: \(error)")
            // If we can't read logs, assume healthy to avoid false positives
            return true
        }
    }

    // MARK: - Activation Methods

    /// Activates the VirtualHIDDevice Manager
    /// This is equivalent to running the manager app with the 'activate' command
    func activateManager() async -> Bool {
        guard detectInstallation() else {
            AppLogger.shared.log("❌ [VHIDManager] Cannot activate - manager app not installed")
            return false
        }

        AppLogger.shared.log("🔧 [VHIDManager] Activating VHIDDevice Manager...")

        return await executeWithAdminPrivileges(
            command: "\(Self.vhidManagerPath) activate",
            description: "Activate VirtualHIDDevice Manager"
        )
    }

    /// Execute a command with administrator privileges using osascript
    private func executeWithAdminPrivileges(command: String, description: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                AppLogger.shared.log("🔧 [VHIDManager] Requesting admin privileges for: \(description)")

                // Use osascript to request admin privileges with proper password dialog
                let osascriptCommand =
                    "do shell script \"\(command)\" with administrator privileges with prompt \"KeyPath needs to \(description.lowercased()).\""

                let osascriptTask = Process()
                osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                osascriptTask.arguments = ["-e", osascriptCommand]

                let pipe = Pipe()
                osascriptTask.standardOutput = pipe
                osascriptTask.standardError = pipe

                do {
                    try osascriptTask.run()
                    osascriptTask.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if osascriptTask.terminationStatus == 0 {
                        AppLogger.shared.log("✅ [VHIDManager] \(description) completed successfully")

                        // Wait a moment for the activation to take effect
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                            // Verify activation worked
                            let activated = self.detectActivation()
                            AppLogger.shared.log("🔍 [VHIDManager] Post-activation verification: \(activated)")
                            continuation.resume(returning: activated)
                        }
                    } else {
                        AppLogger.shared.log(
                            "❌ [VHIDManager] \(description) failed with status \(osascriptTask.terminationStatus): \(output)"
                        )
                        continuation.resume(returning: false)
                    }
                } catch {
                    AppLogger.shared.log("❌ [VHIDManager] Error executing \(description): \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Comprehensive status check - returns detailed information about VHIDDevice state
    func getDetailedStatus() -> VHIDDeviceStatus {
        let installed = detectInstallation()
        let activated = detectActivation()
        let running = detectRunning()
        let connectionHealthy = detectConnectionHealth()

        return VHIDDeviceStatus(
            managerInstalled: installed,
            managerActivated: activated,
            daemonRunning: running,
            connectionHealthy: connectionHealthy
        )
    }
}

// MARK: - Supporting Types

/// Detailed status information for VHIDDevice components
struct VHIDDeviceStatus {
    let managerInstalled: Bool
    let managerActivated: Bool
    let daemonRunning: Bool
    let connectionHealthy: Bool

    /// True if all components are ready for use
    var isFullyOperational: Bool {
        managerInstalled && managerActivated && daemonRunning && connectionHealthy
    }

    /// Description of current status for logging/debugging
    var description: String {
        """
        VHIDDevice Status:
        - Manager Installed: \(managerInstalled)
        - Manager Activated: \(managerActivated)
        - Daemon Running: \(daemonRunning)
        - Connection Healthy: \(connectionHealthy)
        - Fully Operational: \(isFullyOperational)
        """
    }
}
