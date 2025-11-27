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

    // Test seam: allow mocking shell command results during unit tests
    nonisolated(unsafe) static var testShellProvider: ((String) -> String)?

    // Test seam: allow injecting installed version during unit tests
    nonisolated(unsafe) static var testInstalledVersionProvider: (() -> String?)?

    // Version compatibility for kanata - uses bundled driver as single source of truth
    // NOTE: Kanata v1.10.0+ requires Karabiner-DriverKit-VirtualHIDDevice v6.0.0
    // Updated Nov 2025 when Kanata v1.10.0 was released
    private static var requiredDriverVersionMajor: Int { WizardSystemPaths.bundledVHIDDriverMajorVersion }
    static var requiredDriverVersionString: String { WizardSystemPaths.bundledVHIDDriverVersion }
    private static let currentKanataVersion = "1.10.0" // Current supported Kanata version

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
    func detectRunning() async -> Bool {
        let maxAttempts = FeatureFlags.shared.startupModeActive ? 1 : 2
        let retryDelay: UInt64 = 500_000_000 // 0.5s

        for attempt in 1 ... maxAttempts {
            switch await evaluateDaemonProcess() {
            case .healthy:
                return true
            case .notRunning:
                if attempt < maxAttempts {
                    AppLogger.shared.log(
                        "⏳ [VHIDManager] Daemon reported not running; retrying shortly to avoid false positives"
                    )
                    try? await Task.sleep(nanoseconds: retryDelay)
                    continue
                }
                return false
            case .timeout:
                // Treat timeout as inconclusive; use fallback launchctl check before giving up
                if await Self.fastLaunchctlCheck() { return true }
                if attempt < maxAttempts {
                    AppLogger.shared.log(
                        "⏳ [VHIDManager] Timeout while checking daemon; retrying to avoid false negatives"
                    )
                    try? await Task.sleep(nanoseconds: retryDelay)
                    continue
                }
                return false
            case .duplicateProcesses, .error:
                return false
            }
        }
        return false
    }

    private struct TimeoutError: Error {}

    private func evaluateDaemonProcess() async -> DaemonHealthState {
        // During startup mode, use fast non-blocking check to avoid false negatives
        // while still preventing UI freezes from Process() execution
        if FeatureFlags.shared.startupModeActive {
            AppLogger.shared.log(
                "🔍 [VHIDManager] Startup mode - using fast launchctl check to prevent UI freeze")
            // Use launchctl list which is much faster than pgrep and doesn't block UI
            let result = await shellAsync("/bin/launchctl list com.keypath.karabiner-vhiddaemon")
            let isRunning = result.contains("\"PID\"")
            AppLogger.shared.log(
                "🔍 [VHIDManager] Startup mode fast check: daemon \(isRunning ? "running" : "not running")")
            return isRunning ? .healthy : .notRunning
        }

        return await Task.detached {
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
                    AppLogger.shared.log(
                        "❌ [VHIDManager] (test) UNHEALTHY: Multiple VHIDDevice daemon processes detected (\(processCount))"
                    )
                    AppLogger.shared.log("❌ [VHIDManager] (test) PIDs: \(pids.joined(separator: ", "))")
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    AppLogger.shared.log(
                        "🔍 [VHIDManager] (test) VHIDDevice daemon health: UNHEALTHY (duplicates) (took \(String(format: "%.3f", duration))s)"
                    )
                    return .duplicateProcesses
                }
                AppLogger.shared.log(
                    "🔍 [VHIDManager] (test) VHIDDevice daemon health: HEALTHY (single instance)")
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

                // Race process execution against timeout
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            task.waitUntilExit()
                        }
                        group.addTask {
                            try await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                            throw TimeoutError()
                        }
                        try await group.next()
                        group.cancelAll()
                    }
                } catch is TimeoutError {
                    task.terminate()
                    // Fallback to a fast launchctl check so we don't flip the wizard red on a hung pgrep
                    let launchctlRunning = await Self.fastLaunchctlCheck()
                    AppLogger.shared.log(
                        "⚠️ [VHIDManager] VHIDDevice process check timed out after 3s - fallback launchctl says running=\(launchctlRunning)"
                    )
                    return launchctlRunning ? .healthy : .timeout
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let isRunning =
                    task.terminationStatus == 0
                        && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                // Check for duplicate processes - UNHEALTHY if more than one
                if isRunning {
                    let pids = output.trimmingCharacters(in: .whitespacesAndNewlines).components(
                        separatedBy: .newlines)
                    let processCount = pids.filter { !$0.isEmpty }.count
                    if processCount > 1 {
                        AppLogger.shared.log(
                            "❌ [VHIDManager] UNHEALTHY: Multiple VHIDDevice daemon processes detected (\(processCount)) - should only be 1"
                        )
                        AppLogger.shared.log("❌ [VHIDManager] PIDs: \(pids.joined(separator: ", "))")
                        let duration = CFAbsoluteTimeGetCurrent() - startTime
                        AppLogger.shared.log(
                            "🔍 [VHIDManager] VHIDDevice daemon health: UNHEALTHY (duplicates) (took \(String(format: "%.3f", duration))s)"
                        )
                        return .duplicateProcesses
                    }
                }

                let duration = CFAbsoluteTimeGetCurrent() - startTime
                AppLogger.shared.log(
                    "🔍 [VHIDManager] VHIDDevice daemon health: \(isRunning ? "HEALTHY" : "NOT RUNNING") (took \(String(format: "%.3f", duration))s)"
                )
                return isRunning ? .healthy : .notRunning
            } catch {
                AppLogger.shared.log("❌ [VHIDManager] Error checking VHIDDevice processes: \(error)")
                return .error
            }
        }.value
    }

    /// Extremely fast check using launchctl list; used as a fallback when pgrep stalls.
    private static func fastLaunchctlCheck() async -> Bool {
        do {
            let result = try await SubprocessRunner.shared.launchctl("list", ["com.keypath.karabiner-vhiddaemon"])
            return result.stdout.contains("\"PID\"")
        } catch {
            AppLogger.shared.log("❌ [VHIDManager] fastLaunchctlCheck failed: \(error)")
            return false
        }
    }

    /// Get actual PIDs of running VirtualHID daemon processes
    /// Returns array of PID strings, empty if no processes found
    func getDaemonPIDs() async -> [String] {
        // Skip during startup to prevent blocking
        if FeatureFlags.shared.startupModeActive {
            return []
        }

        // Test seam for unit tests
        if TestEnvironment.isRunningTests, let provider = Self.testPIDProvider {
            return provider().filter { !$0.isEmpty }
        }

        let pids = await SubprocessRunner.shared.pgrep(Self.vhidDeviceRunningCheck)
        return pids.map { String($0) }
    }

    /// Lightweight health check using launchctl. Returns:
    /// - true if launchctl print succeeds,
    /// - false if launchctl reports the service but unhealthy,
    /// - nil if the call fails (permission/lookup).
    func checkLaunchctlHealth() async -> Bool? {
        do {
            let result = try await SubprocessRunner.shared.launchctl("print", ["system/com.keypath.karabiner-vhiddaemon"])

            guard result.exitCode == 0 else {
                AppLogger.shared.log(
                    "⚠️ [VHIDManager] launchctl health check exit=\(result.exitCode)")
                return false
            }

            // Consider it healthy if a PID line exists
            let healthy = result.stdout.contains("pid =") || result.stdout.contains("\"PID\"")
            AppLogger.shared.log(
                "🔍 [VHIDManager] launchctl health check healthy=\(healthy)")
            return healthy
        } catch {
            AppLogger.shared.log("⚠️ [VHIDManager] launchctl health check failed: \(error)")
            return nil
        }
    }

    /// Checks if VirtualHID daemon is functioning correctly (wizard prerequisite)
    /// Wizard now treats this as a pure process health check; log parsing lives in DiagnosticsView
    func detectConnectionHealth() async -> Bool {
        let isRunning = await detectRunning()
        // 🔍 DEBUG: Log the result to understand health check behavior
        AppLogger.shared.log("🔍 [VHIDManager] detectConnectionHealth() -> isRunning=\(isRunning)")
        if !isRunning {
            AppLogger.shared.log("🔍 [VHIDManager] Process health check failed - daemon not running")
        } else {
            AppLogger.shared.log("✅ [VHIDManager] Process health check passed - daemon is running")
        }
        return isRunning
    }

    // MARK: - Version Detection

    /// Gets the installed VirtualHIDDevice daemon version
    func getInstalledVersion() -> String? {
        // Test seam: allow injecting version during tests
        if let testProvider = Self.testInstalledVersionProvider {
            return testProvider()
        }

        guard FileManager.default.fileExists(atPath: Self.vhidDeviceDaemonInfoPlistPath) else {
            AppLogger.shared.log(
                "🔍 [VHIDManager] Info.plist not found at \(Self.vhidDeviceDaemonInfoPlistPath)")
            return nil
        }

        guard let plistData = FileManager.default.contents(atPath: Self.vhidDeviceDaemonInfoPlistPath)
        else {
            AppLogger.shared.log("❌ [VHIDManager] Failed to read Info.plist")
            return nil
        }

        do {
            let plist =
                try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
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
            AppLogger.shared.log(
                "  - Required: v\(Self.requiredDriverVersionString) (major: \(Self.requiredDriverVersionMajor))"
            )
            AppLogger.shared.log("  - Kanata \(Self.currentKanataVersion) requires driver v\(Self.requiredDriverVersionMajor).x")
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

            You have Karabiner-DriverKit-VirtualHIDDevice v\(installedVersion) installed, but Kanata v\(Self.currentKanataVersion) requires v\(Self.requiredDriverVersionString).

            KeyPath will install the bundled v\(Self.requiredDriverVersionString) for you.
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

    /// Execute a command with administrator privileges.
    /// Uses sudo if KEYPATH_USE_SUDO=1 is set (for testing), otherwise uses osascript.
    private func executeWithAdminPrivileges(command: String, description: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                AppLogger.shared.log("🔧 [VHIDManager] Requesting admin privileges for: \(description)")

                // Use centralized PrivilegedCommandRunner (uses sudo if KEYPATH_USE_SUDO=1, otherwise osascript)
                let result = PrivilegedCommandRunner.execute(
                    command: command,
                    prompt: "KeyPath needs to \(description.lowercased())."
                )

                if result.success {
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
                        "❌ [VHIDManager] \(description) failed with status \(result.exitCode): \(result.output)"
                    )
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
        do {
            let listResult = try await SubprocessRunner.shared.run(
                "/usr/bin/systemextensionsctl",
                args: ["list"],
                timeout: 10
            )

            // Check if our driver extension is listed
            let hasKarabinerDriver = listResult.stdout.contains("Karabiner-DriverKit-VirtualHIDDevice")

            if !hasKarabinerDriver {
                AppLogger.shared.log(
                    "ℹ️ [VHIDManager] No Karabiner driver extensions found - nothing to uninstall")
                return true
            }

            AppLogger.shared.log("📋 [VHIDManager] Found Karabiner driver extension(s) to uninstall")

            // Uninstall using systemextensionsctl with admin privileges
            let uninstallCommand =
                "/usr/bin/systemextensionsctl uninstall \(Self.driverTeamID) \(Self.driverBundleID)"

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
                AppLogger.shared.log(
                    "⚠️ [VHIDManager] Uninstall command completed - may require restart to take full effect")
                // Still return true since we attempted uninstall
                return true
            }

        } catch {
            AppLogger.shared.log("⚠️ [VHIDManager] Error checking/uninstalling drivers: \(error)")
            // Don't fail - proceed with installation anyway
            return true
        }
    }

    /// Installs the correct version of Karabiner-DriverKit-VirtualHIDDevice
    /// Prefers bundled pkg (no download required), falls back to download if missing
    func downloadAndInstallCorrectVersion() async -> Bool {
        AppLogger.shared.log(
            "🔧 [VHIDManager] Installing v\(Self.requiredDriverVersionString)")

        // Step 1: Clean up existing driver versions first
        AppLogger.shared.log("🔧 [VHIDManager] Step 1/4: Cleaning up existing driver versions...")
        let uninstallSuccess = await uninstallAllDriverVersions()
        if !uninstallSuccess {
            AppLogger.shared.log(
                "⚠️ [VHIDManager] Cleanup had issues, but proceeding with installation...")
        }

        // Step 2: Use bundled pkg (required - no download fallback)
        let bundledPkgPath = WizardSystemPaths.bundledVHIDDriverPkgPath
        guard WizardSystemPaths.bundledVHIDDriverPkgExists else {
            AppLogger.shared.error(
                "❌ [VHIDManager] Bundled VHID driver pkg not found at: \(bundledPkgPath). " +
                    "This indicates a corrupt KeyPath installation."
            )
            return false
        }
        AppLogger.shared.log("📦 [VHIDManager] Step 2/3: Using bundled VHID driver pkg")
        let pkgPath = URL(fileURLWithPath: bundledPkgPath)

        // Step 3: Install the package
        AppLogger.shared.log("🔧 [VHIDManager] Step 3/3: Installing package...")

        let installResult = await executeWithAdminPrivileges(
            command: "/usr/sbin/installer -pkg \"\(pkgPath.path)\" -target /",
            description:
            "Install Karabiner-DriverKit-VirtualHIDDevice v\(Self.requiredDriverVersionString)"
        )

        if installResult {
            AppLogger.shared.log(
                "✅ [VHIDManager] Successfully installed v\(Self.requiredDriverVersionString)")

            // Wait for installation to complete
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

            // Activate the newly installed version
            AppLogger.shared.log("🔧 [VHIDManager] Activating newly installed driver...")
            let activateResult = await activateManager()

            if activateResult {
                AppLogger.shared.log("✅ [VHIDManager] Driver activated successfully")
            } else {
                AppLogger.shared.log(
                    "⚠️ [VHIDManager] Driver installed but activation may need user approval")
            }
            return true // Installation succeeded regardless of activation status
        } else {
            AppLogger.shared.log("❌ [VHIDManager] Installation failed")
            return false
        }
    }

    /// Comprehensive status check - returns detailed information about VHIDDevice state
    func getDetailedStatus() async -> VHIDDeviceStatus {
        let installed = detectInstallation()
        let activated = detectActivation()
        let running = await detectRunning()
        let connectionHealthy = await detectConnectionHealth()

        return VHIDDeviceStatus(
            managerInstalled: installed,
            managerActivated: activated,
            daemonRunning: running,
            connectionHealthy: connectionHealthy
        )
    }

    // MARK: - Helper Functions

    /// Fast shell command execution using SubprocessRunner
    private func shellAsync(_ command: String) async -> String {
        // Test seam: use mock shell results in tests
        if TestEnvironment.isRunningTests, let provider = Self.testShellProvider {
            return provider(command)
        }

        do {
            let result = try await SubprocessRunner.shared.run(
                "/bin/sh",
                args: ["-c", command],
                timeout: 10
            )
            return result.stdout
        } catch {
            return ""
        }
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
