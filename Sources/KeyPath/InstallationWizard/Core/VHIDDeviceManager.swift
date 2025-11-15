import Foundation
import KeyPathCore

/// Manages the Karabiner VirtualHIDDevice Manager component
/// This is critical for keyboard remapping functionality on macOS
final class VHIDDeviceManager: @unchecked Sendable {
    private enum DaemonHealthState {
        case healthy
        case notRunning
        case duplicateProcesses
        case timeout
        case error
    }

    // MARK: - Constants

    private static let vhidManagerPath =
        "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
    private static let vhidManagerBundleID = "org.pqrs.Karabiner-VirtualHIDDevice-Manager"
    private static let vhidDeviceDaemonPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    private static let vhidDeviceDaemonInfoPlistPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/Info.plist"
    private static let vhidDeviceRunningCheck = "Karabiner-VirtualHIDDevice-Daemon"

    // Test seam: allow injecting PID provider during unit tests
    nonisolated(unsafe) static var testPIDProvider: (() -> [String])?

    // Version compatibility for kanata
    // NOTE: Kanata v1.9.0 requires Karabiner-DriverKit-VirtualHIDDevice v5.0.0
    // Kanata v1.10 will support v6.0.0+ but is currently in pre-release (as of Oct 2025)
    private static let requiredDriverVersionMajor = 5
    private static let requiredDriverVersionString = "5.0.0"
    private static let futureCompatibleVersion = "1.10" // Kanata version that will support v6

    // Driver DriverKit extension identifiers
    private static let driverTeamID = "G43BCU2T37" // pqrs.org team ID
    private static let driverBundleID = "org.pqrs.driver.Karabiner-DriverKit-VirtualHIDDevice"

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
        let maxAttempts = FeatureFlags.shared.startupModeActive ? 1 : 2
        let retryDelay: useconds_t = 500_000 // 0.5s between attempts to allow daemon to settle

        for attempt in 1 ... maxAttempts {
            switch evaluateDaemonProcess() {
            case .healthy:
                return true
            case .notRunning:
                if attempt < maxAttempts {
                    AppLogger.shared.log("⏳ [VHIDManager] Daemon reported not running; retrying shortly to avoid false positives")
                    usleep(retryDelay)
                    continue
                }
                return false
            case .duplicateProcesses, .timeout, .error:
                return false
            }
        }
        return false
    }

    private func evaluateDaemonProcess() -> DaemonHealthState {
        // Skip daemon check during startup to prevent blocking
        if FeatureFlags.shared.startupModeActive {
            AppLogger.shared.log("🔍 [VHIDManager] Startup mode - skipping VHIDDevice process check to prevent UI freeze")
            return .notRunning
        }

        // Test seam: allow mocked PID list in tests
        if TestEnvironment.isRunningTests, let provider = Self.testPIDProvider {
            let startTime = CFAbsoluteTimeGetCurrent()
            let pids = provider().filter { !$0.isEmpty }
            let processCount = pids.count
            if processCount == 0 {
                AppLogger.shared.log("🔍 [VHIDManager] (test) VHIDDevice daemon health: NOT RUNNING")
                return .notRunning
            }
            if processCount > 1 {
                AppLogger.shared.log("❌ [VHIDManager] (test) UNHEALTHY: Multiple VHIDDevice daemon processes detected (\(processCount))")
                AppLogger.shared.log("❌ [VHIDManager] (test) PIDs: \(pids.joined(separator: ", "))")
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                AppLogger.shared.log("🔍 [VHIDManager] (test) VHIDDevice daemon health: UNHEALTHY (duplicates) (took \(String(format: "%.3f", duration))s)")
                return .duplicateProcesses
            }
            AppLogger.shared.log("🔍 [VHIDManager] (test) VHIDDevice daemon health: HEALTHY (single instance)")
            return .healthy
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
                return .timeout
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let isRunning =
                task.terminationStatus == 0
                    && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Check for duplicate processes - UNHEALTHY if more than one
            if isRunning {
                let pids = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
                let processCount = pids.filter { !$0.isEmpty }.count
                if processCount > 1 {
                    AppLogger.shared.log("❌ [VHIDManager] UNHEALTHY: Multiple VHIDDevice daemon processes detected (\(processCount)) - should only be 1")
                    AppLogger.shared.log("❌ [VHIDManager] PIDs: \(pids.joined(separator: ", "))")
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    AppLogger.shared.log("🔍 [VHIDManager] VHIDDevice daemon health: UNHEALTHY (duplicates) (took \(String(format: "%.3f", duration))s)")
                    return .duplicateProcesses
                }
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            AppLogger.shared.log("🔍 [VHIDManager] VHIDDevice daemon health: \(isRunning ? "HEALTHY" : "NOT RUNNING") (took \(String(format: "%.3f", duration))s)")
            return isRunning ? .healthy : .notRunning
        } catch {
            AppLogger.shared.log("❌ [VHIDManager] Error checking VHIDDevice processes: \(error)")
            return .error
        }
    }

    /// Get actual PIDs of running VirtualHID daemon processes
    /// Returns array of PID strings, empty if no processes found
    func getDaemonPIDs() -> [String] {
        // Skip during startup to prevent blocking
        if FeatureFlags.shared.startupModeActive {
            return []
        }

        // Test seam for unit tests
        if TestEnvironment.isRunningTests, let provider = Self.testPIDProvider {
            return provider().filter { !$0.isEmpty }
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", Self.vhidDeviceRunningCheck]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            guard task.terminationStatus == 0 else {
                return []
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let pids = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }

            return pids
        } catch {
            AppLogger.shared.log("❌ [VHIDManager] Error getting daemon PIDs: \(error)")
            return []
        }
    }

    /// Checks if VirtualHID daemon is functioning correctly (wizard prerequisite)
    /// Wizard now treats this as a pure process health check; log parsing lives in DiagnosticsView
    func detectConnectionHealth() -> Bool {
        let isRunning = detectRunning()
        if !isRunning {
            AppLogger.shared.log("🔍 [VHIDManager] Process health check failed - daemon not running")
        }
        return isRunning
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

            📝 Note: Kanata v\(Self.futureCompatibleVersion) (currently in pre-release) will support v6.0.0+. Once v\(Self
                .futureCompatibleVersion) is released and stable, we'll update KeyPath to use the newer driver version.
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

                // Properly escape command for AppleScript (escape backslashes first, then quotes)
                let escapedCommand = command
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")

                // Use osascript to request admin privileges with proper password dialog
                let osascriptCommand =
                    "do shell script \"\(escapedCommand)\" with administrator privileges with prompt \"KeyPath needs to \(description.lowercased()).\""

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

    /// Uninstalls all existing Karabiner-DriverKit-VirtualHIDDevice versions
    /// This ensures a clean slate before installing the correct version
    func uninstallAllDriverVersions() async -> Bool {
        AppLogger.shared.log("🧹 [VHIDManager] Uninstalling all existing driver versions...")

        // First, check if there are any DriverKit extensions to uninstall
        let listTask = Process()
        listTask.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        listTask.arguments = ["list"]

        let listPipe = Pipe()
        listTask.standardOutput = listPipe
        listTask.standardError = listPipe

        do {
            try listTask.run()
            listTask.waitUntilExit()

            let data = listPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Check if our driver extension is listed
            let hasKarabinerDriver = output.contains("Karabiner-DriverKit-VirtualHIDDevice")

            if !hasKarabinerDriver {
                AppLogger.shared.log("ℹ️ [VHIDManager] No Karabiner driver extensions found - nothing to uninstall")
                return true
            }

            AppLogger.shared.log("📋 [VHIDManager] Found Karabiner driver extension(s) to uninstall")

            // Uninstall using systemextensionsctl with admin privileges
            let uninstallCommand = "/usr/bin/systemextensionsctl uninstall \(Self.driverTeamID) \(Self.driverBundleID)"

            let uninstallResult = await executeWithAdminPrivileges(
                command: uninstallCommand,
                description: "Uninstall existing Karabiner driver versions"
            )

            if uninstallResult {
                AppLogger.shared.log("✅ [VHIDManager] Successfully uninstalled existing driver version(s)")

                // Wait for uninstallation to complete
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                return true
            } else {
                AppLogger.shared.log("⚠️ [VHIDManager] Uninstall command completed - may require restart to take full effect")
                // Still return true since we attempted uninstall
                return true
            }

        } catch {
            AppLogger.shared.log("⚠️ [VHIDManager] Error checking/uninstalling drivers: \(error)")
            // Don't fail - proceed with installation anyway
            return true
        }
    }

    /// Downloads and installs the correct version of Karabiner-DriverKit-VirtualHIDDevice
    func downloadAndInstallCorrectVersion() async -> Bool {
        AppLogger.shared.log("🔧 [VHIDManager] Downloading and installing v\(Self.requiredDriverVersionString)")

        // Step 1: Clean up existing driver versions first
        AppLogger.shared.log("🔧 [VHIDManager] Step 1/4: Cleaning up existing driver versions...")
        let uninstallSuccess = await uninstallAllDriverVersions()
        if !uninstallSuccess {
            AppLogger.shared.log("⚠️ [VHIDManager] Cleanup had issues, but proceeding with installation...")
        }

        // Download URL for v5.0.0
        AppLogger.shared.log("🔧 [VHIDManager] Step 2/4: Downloading v\(Self.requiredDriverVersionString)...")
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
            AppLogger.shared.log("🔧 [VHIDManager] Step 3/4: Installing package...")

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
                AppLogger.shared.log("🔧 [VHIDManager] Step 4/4: Activating newly installed driver...")
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
