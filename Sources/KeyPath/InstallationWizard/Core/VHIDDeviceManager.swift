import Foundation

/// Manages the Karabiner VirtualHIDDevice Manager component
/// This is critical for keyboard remapping functionality on macOS
final class VHIDDeviceManager: @unchecked Sendable {
    // MARK: - Constants

    private static let vhidManagerPath =
        "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    private static let vhidManagerBundleID = "org.pqrs.Karabiner-VirtualHIDDevice-Manager"
    private static let vhidDeviceDaemonPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    private static let vhidDeviceDaemonInfoPlistPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/Info.plist"
    private static let vhidDeviceRunningCheck = "Karabiner-VirtualHIDDevice-Daemon"

    // Version compatibility for kanata
    // NOTE: Kanata v1.9.0 requires Karabiner-DriverKit-VirtualHIDDevice v5.0.0
    // Kanata v1.10 will support v6.0.0+ but is currently in pre-release (as of Oct 2025)
    private static let requiredDriverVersionMajor = 5
    private static let requiredDriverVersionString = "5.0.0"
    private static let futureCompatibleVersion = "1.10" // Kanata version that will support v6

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
        // Skip daemon check during startup to prevent blocking
        if ProcessInfo.processInfo.environment["KEYPATH_STARTUP_MODE"] == "1" {
            AppLogger.shared.log("🔍 [VHIDManager] Startup mode - skipping VHIDDevice process check to prevent UI freeze")
            return false // Assume not running during startup
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", Self.vhidDeviceRunningCheck]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            try task.run()
            
            // Use DispatchGroup to implement timeout for process execution
            let group = DispatchGroup()
            group.enter()
            
            DispatchQueue.global().async {
                task.waitUntilExit()
                group.leave()
            }
            
            let timeoutResult = group.wait(timeout: .now() + 2.0) // 2 second timeout
            if timeoutResult == .timedOut {
                task.terminate()
                AppLogger.shared.log("⚠️ [VHIDManager] VHIDDevice process check timed out after 2s - assuming not running")
                return false
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let isRunning =
                task.terminationStatus == 0
                    && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Check for duplicate processes
            if isRunning {
                let pids = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
                let processCount = pids.filter { !$0.isEmpty }.count
                if processCount > 1 {
                    AppLogger.shared.log("⚠️ [VHIDManager] WARNING: Multiple VHIDDevice daemon processes detected (\(processCount)) - should only be 1")
                    AppLogger.shared.log("⚠️ [VHIDManager] PIDs: \(pids.joined(separator: ", "))")
                }
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            AppLogger.shared.log("🔍 [VHIDManager] VHIDDevice processes running: \(isRunning) (took \(String(format: "%.3f", duration))s)")
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

            let driverNotActivatedErrors = recentLines.filter { line in
                line.contains("driver is not activated")
            }

            let successfulConnections = recentLines.filter { line in
                line.contains("driver_connected 1")
            }

            // Fatal error: driver not activated means VirtualHID is not accessible at all
            if !driverNotActivatedErrors.isEmpty {
                AppLogger.shared.log("❌ [VHIDManager] FATAL: VirtualHID driver not activated (\(driverNotActivatedErrors.count) errors)")
                return false
            }

            // If we see recent connection failures without recent successes, consider unhealthy
            let hasRecentFailures = connectionFailures.count > 5
            let hasRecentSuccess = !successfulConnections.isEmpty

            let isHealthy = !hasRecentFailures || hasRecentSuccess

            AppLogger.shared.log("🔍 [VHIDManager] Connection health check:")
            AppLogger.shared.log("  - Recent failures: \(connectionFailures.count)")
            AppLogger.shared.log("  - Recent successes: \(successfulConnections.count)")
            AppLogger.shared.log("  - Driver activation errors: \(driverNotActivatedErrors.count)")
            AppLogger.shared.log("  - Health status: \(isHealthy)")

            return isHealthy
        }
    }

    // MARK: - Version Detection

    /// Gets the installed VirtualHIDDevice daemon version
    func getInstalledVersion() -> String? {
        guard FileManager.default.fileExists(atPath: Self.vhidDeviceDaemonInfoPlistPath) else {
            AppLogger.shared.log("🔍 [VHIDManager] Info.plist not found at \(Self.vhidDeviceDaemonInfoPlistPath)")
            return nil
        }

        guard let plistData = FileManager.default.contents(atPath: Self.vhidDeviceDaemonInfoPlistPath) else {
            AppLogger.shared.log("❌ [VHIDManager] Failed to read Info.plist")
            return nil
        }

        do {
            let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
            let version = plist?["CFBundleShortVersionString"] as? String
            AppLogger.shared.log("🔍 [VHIDManager] Installed daemon version: \(version ?? "unknown")")
            return version
        } catch {
            AppLogger.shared.log("❌ [VHIDManager] Failed to parse Info.plist: \(error)")
            return nil
        }
    }

    /// Checks if the installed driver version is compatible with current kanata
    func hasVersionMismatch() -> Bool {
        guard let installedVersion = getInstalledVersion() else {
            AppLogger.shared.log("⚠️ [VHIDManager] Cannot determine version - assuming no mismatch")
            return false
        }

        // Parse major version
        let versionComponents = installedVersion.split(separator: ".").compactMap { Int($0) }
        guard let majorVersion = versionComponents.first else {
            AppLogger.shared.log("⚠️ [VHIDManager] Cannot parse version \(installedVersion)")
            return false
        }

        let hasMismatch = majorVersion != Self.requiredDriverVersionMajor
        if hasMismatch {
            AppLogger.shared.log("❌ [VHIDManager] Version mismatch detected:")
            AppLogger.shared.log("  - Installed: v\(installedVersion) (major: \(majorVersion))")
            AppLogger.shared.log("  - Required: v\(Self.requiredDriverVersionString) (major: \(Self.requiredDriverVersionMajor))")
            AppLogger.shared.log("  - Note: Kanata \(Self.futureCompatibleVersion)+ will support v6.0.0+")
        } else {
            AppLogger.shared.log("✅ [VHIDManager] Version compatible: v\(installedVersion)")
        }

        return hasMismatch
    }

    /// Gets a user-friendly message about version compatibility
    func getVersionMismatchMessage() -> String? {
        guard let installedVersion = getInstalledVersion() else {
            return nil
        }

        let versionComponents = installedVersion.split(separator: ".").compactMap { Int($0) }
        guard let majorVersion = versionComponents.first else {
            return nil
        }

        if majorVersion != Self.requiredDriverVersionMajor {
            return """
            Version Compatibility Issue

            You have Karabiner-DriverKit-VirtualHIDDevice v\(installedVersion) installed, but the current version of Kanata (v1.9.0) requires v\(Self.requiredDriverVersionString).

            KeyPath will automatically download and install v\(Self.requiredDriverVersionString) for you.

            📝 Note: Kanata v\(Self.futureCompatibleVersion) (currently in pre-release) will support v6.0.0+. Once v\(Self.futureCompatibleVersion) is released and stable, we'll update KeyPath to use the newer driver version.
            """
        }

        return nil
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

    /// Downloads and installs the correct version of Karabiner-DriverKit-VirtualHIDDevice
    func downloadAndInstallCorrectVersion() async -> Bool {
        AppLogger.shared.log("🔧 [VHIDManager] Downloading and installing v\(Self.requiredDriverVersionString)")

        // Download URL for v5.0.0
        let downloadURL = "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v\(Self.requiredDriverVersionString)/Karabiner-DriverKit-VirtualHIDDevice-\(Self.requiredDriverVersionString).pkg"
        let tmpDir = FileManager.default.temporaryDirectory
        let pkgPath = tmpDir.appendingPathComponent("Karabiner-DriverKit-VirtualHIDDevice-\(Self.requiredDriverVersionString).pkg")

        // Download the package
        AppLogger.shared.log("📥 [VHIDManager] Downloading from \(downloadURL)")

        do {
            let (localURL, response) = try await URLSession.shared.download(from: URL(string: downloadURL)!)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                AppLogger.shared.log("❌ [VHIDManager] Download failed - HTTP status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return false
            }

            // Move downloaded file to temp location
            try FileManager.default.moveItem(at: localURL, to: pkgPath)
            AppLogger.shared.log("✅ [VHIDManager] Downloaded to \(pkgPath.path)")

            // Install the package using installer command
            AppLogger.shared.log("📦 [VHIDManager] Installing package...")

            let installResult = await executeWithAdminPrivileges(
                command: "/usr/sbin/installer -pkg \"\(pkgPath.path)\" -target /",
                description: "Install Karabiner-DriverKit-VirtualHIDDevice v\(Self.requiredDriverVersionString)"
            )

            // Clean up downloaded package
            try? FileManager.default.removeItem(at: pkgPath)

            if installResult {
                AppLogger.shared.log("✅ [VHIDManager] Successfully installed v\(Self.requiredDriverVersionString)")

                // Wait for installation to complete
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

                // Activate the newly installed version
                AppLogger.shared.log("🔧 [VHIDManager] Activating newly installed driver...")
                let activateResult = await activateManager()

                if activateResult {
                    AppLogger.shared.log("✅ [VHIDManager] Driver activated successfully")
                    return true
                } else {
                    AppLogger.shared.log("⚠️ [VHIDManager] Driver installed but activation may need user approval")
                    return true // Still return true since installation succeeded
                }
            } else {
                AppLogger.shared.log("❌ [VHIDManager] Installation failed")
                return false
            }

        } catch {
            AppLogger.shared.log("❌ [VHIDManager] Error downloading/installing: \(error)")
            return false
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
