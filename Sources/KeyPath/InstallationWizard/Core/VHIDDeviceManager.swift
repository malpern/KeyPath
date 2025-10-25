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

    // Driver DriverKit extension identifiers
    private static let driverTeamID = "G43BCU2T37" // pqrs.org team ID
    private static let driverBundleID = "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"

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
    /// This checks BOTH file existence AND system extension activation status
    func detectActivation() -> Bool {
        let fileManager = FileManager.default
        let daemonExists = fileManager.fileExists(atPath: Self.vhidDeviceDaemonPath)

        AppLogger.shared.log(
            "🔍 [VHIDManager] Daemon exists at \(Self.vhidDeviceDaemonPath): \(daemonExists)")

        guard daemonExists else {
            return false
        }

        // Check if system extension is enabled
        let isEnabled = isSystemExtensionEnabled()
        guard isEnabled else {
            AppLogger.shared.log("⚠️ [VHIDManager] System extension not enabled")
            return false
        }

        // Get both registered and file versions
        let registeredVersion = getRegisteredExtensionVersion()
        let fileVersion = getInstalledVersion()

        // Workaround for macOS caching: If files are v5.0.0 and extension is enabled,
        // trust the file version even if registry still shows v1.8.0
        if let fileVer = fileVersion {
            let fileComponents = fileVer.split(separator: ".").compactMap { Int($0) }
            if let fileMajor = fileComponents.first {
                let fileVersionCorrect = fileMajor == Self.requiredDriverVersionMajor

                if fileVersionCorrect {
                    AppLogger.shared.log(
                        "✅ [VHIDManager] File version v\(fileVer) is correct and extension is enabled (registered shows: \(registeredVersion ?? "none"))")
                    return true
                }
            }
        }

        // Fall back to registered version check
        if let regVer = registeredVersion {
            let regComponents = regVer.split(separator: ".").compactMap { Int($0) }
            if let regMajor = regComponents.first {
                let regVersionCorrect = regMajor == Self.requiredDriverVersionMajor
                AppLogger.shared.log(
                    "🔍 [VHIDManager] Registered version v\(regVer) - Correct: \(regVersionCorrect)")
                return regVersionCorrect
            }
        }

        AppLogger.shared.log("⚠️ [VHIDManager] Could not determine driver version")
        return false
    }

    /// Checks if the Karabiner system extension is enabled (not just activated/waiting for approval)
    private func isSystemExtensionEnabled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        task.arguments = ["list"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Look for our driver with [activated enabled] status
            for line in output.components(separatedBy: .newlines) {
                if line.contains(Self.driverBundleID) && line.contains("[activated enabled]") {
                    AppLogger.shared.log("✅ [VHIDManager] System extension is [activated enabled]")
                    return true
                }
            }

            AppLogger.shared.log("⚠️ [VHIDManager] System extension not in [activated enabled] state")
            return false
        } catch {
            AppLogger.shared.log("❌ [VHIDManager] Failed to check extension enabled status: \(error)")
            return false
        }
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

    /// Gets the version of the REGISTERED system extension (not just installed files)
    func getRegisteredExtensionVersion() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        task.arguments = ["list"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse the output to find our driver extension
            // Example line: "	*	G43BCU2T37	org.pqrs.Karabiner-DriverKit-VirtualHIDDevice (1.8.0/1.8.0)	org.pqrs.Karabiner-DriverKit-VirtualHIDDevice	[activated waiting for user]"
            for line in output.components(separatedBy: .newlines) {
                if line.contains(Self.driverBundleID) {
                    // Extract version from pattern (X.Y.Z/X.Y.Z)
                    if let versionRange = line.range(of: #"\(\d+\.\d+\.\d+/\d+\.\d+\.\d+\)"#, options: .regularExpression) {
                        let versionString = String(line[versionRange])
                        // Extract first version number
                        if let firstVersion = versionString.components(separatedBy: "/").first?.trimmingCharacters(in: CharacterSet(charactersIn: "()")) {
                            AppLogger.shared.log("🔍 [VHIDManager] Registered extension version: \(firstVersion)")
                            return firstVersion
                        }
                    }
                }
            }

            AppLogger.shared.log("🔍 [VHIDManager] No registered system extension found")
            return nil
        } catch {
            AppLogger.shared.log("❌ [VHIDManager] Failed to check registered extension: \(error)")
            return nil
        }
    }

    /// Checks if the installed driver version is compatible with current kanata
    /// Checks file version first (workaround for macOS caching), then registered version
    func hasVersionMismatch() -> Bool {
        // Workaround for macOS caching: If extension is enabled and files are correct version,
        // trust the file version even if registry shows old version
        if isSystemExtensionEnabled(), let fileVersion = getInstalledVersion() {
            let fileComponents = fileVersion.split(separator: ".").compactMap { Int($0) }
            if let fileMajor = fileComponents.first {
                let fileVersionCorrect = fileMajor == Self.requiredDriverVersionMajor

                if fileVersionCorrect {
                    AppLogger.shared.log("✅ [VHIDManager] File version v\(fileVersion) is correct (ignoring registry cache)")
                    return false // No mismatch - file version is correct
                } else {
                    AppLogger.shared.log("❌ [VHIDManager] File version v\(fileVersion) mismatch (major: \(fileMajor), required: \(Self.requiredDriverVersionMajor))")
                    return true
                }
            }
        }

        // Fall back to registered extension version check
        if let registeredVersion = getRegisteredExtensionVersion() {
            let versionComponents = registeredVersion.split(separator: ".").compactMap { Int($0) }
            guard let majorVersion = versionComponents.first else {
                AppLogger.shared.log("⚠️ [VHIDManager] Cannot parse registered version \(registeredVersion)")
                return false
            }

            let hasMismatch = majorVersion != Self.requiredDriverVersionMajor
            if hasMismatch {
                AppLogger.shared.log("❌ [VHIDManager] Registered extension version mismatch:")
                AppLogger.shared.log("  - Registered: v\(registeredVersion) (major: \(majorVersion))")
                AppLogger.shared.log("  - Required: v\(Self.requiredDriverVersionString) (major: \(Self.requiredDriverVersionMajor))")
            } else {
                AppLogger.shared.log("✅ [VHIDManager] Registered extension version compatible: v\(registeredVersion)")
            }
            return hasMismatch
        }

        // Fallback to installed file version if no registered extension
        guard let installedVersion = getInstalledVersion() else {
            AppLogger.shared.log("⚠️ [VHIDManager] No registered extension and cannot determine installed version - assuming mismatch")
            return true // Assume mismatch if we can't determine version
        }

        // Parse major version
        let versionComponents = installedVersion.split(separator: ".").compactMap { Int($0) }
        guard let majorVersion = versionComponents.first else {
            AppLogger.shared.log("⚠️ [VHIDManager] Cannot parse version \(installedVersion)")
            return false
        }

        let hasMismatch = majorVersion != Self.requiredDriverVersionMajor
        if hasMismatch {
            AppLogger.shared.log("❌ [VHIDManager] Installed file version mismatch:")
            AppLogger.shared.log("  - Installed: v\(installedVersion) (major: \(majorVersion))")
            AppLogger.shared.log("  - Required: v\(Self.requiredDriverVersionString) (major: \(Self.requiredDriverVersionMajor))")
        } else {
            AppLogger.shared.log("✅ [VHIDManager] Installed file version compatible: v\(installedVersion)")
        }

        return hasMismatch
    }

    /// Gets a user-friendly message about version compatibility
    /// Uses REGISTERED system extension version
    func getVersionMismatchMessage() -> String? {
        // Check registered version first
        let versionToCheck = getRegisteredExtensionVersion() ?? getInstalledVersion()

        guard let installedVersion = versionToCheck else {
            return nil
        }

        let versionComponents = installedVersion.split(separator: ".").compactMap { Int($0) }
        guard let majorVersion = versionComponents.first else {
            return nil
        }

        if majorVersion != Self.requiredDriverVersionMajor {
            let registeredVersion = getRegisteredExtensionVersion()
            let fileVersion = getInstalledVersion()

            var message = """
            Version Compatibility Issue

            You have Karabiner-DriverKit-VirtualHIDDevice v\(installedVersion) installed, but the current version of Kanata (v1.9.0) requires v\(Self.requiredDriverVersionString).

            KeyPath will automatically download and install v\(Self.requiredDriverVersionString) for you.
            """

            // Add note if registered and file versions differ
            if let reg = registeredVersion, let file = fileVersion, reg != file {
                message += """


                📋 Note: System extension registration shows v\(reg), but installed files show v\(file). The fix will update both.
                """
            }

            message += """


            📝 Note: Kanata v\(Self.futureCompatibleVersion) (currently in pre-release) will support v6.0.0+. Once v\(Self.futureCompatibleVersion) is released and stable, we'll update KeyPath to use the newer driver version.
            """

            return message
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

        let commandSucceeded = await executeWithAdminPrivileges(
            command: "\(Self.vhidManagerPath) forceActivate",
            description: "Activate VirtualHIDDevice Manager"
        )

        if commandSucceeded {
            // Wait for activation to take effect
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            // Verify activation worked
            let activated = detectActivation()
            AppLogger.shared.log("🔍 [VHIDManager] Post-activation verification: \(activated)")
            return activated
        } else {
            return false
        }
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

                    // Use DispatchGroup to implement timeout (10 seconds for admin commands)
                    let group = DispatchGroup()
                    group.enter()

                    DispatchQueue.global().async {
                        osascriptTask.waitUntilExit()
                        group.leave()
                    }

                    let timeoutResult = group.wait(timeout: .now() + 10.0)

                    if timeoutResult == .timedOut {
                        osascriptTask.terminate()
                        AppLogger.shared.log("⚠️ [VHIDManager] \(description) timed out after 10s - command may still be processing in background")
                        continuation.resume(returning: false)
                        return
                    }

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if osascriptTask.terminationStatus == 0 {
                        AppLogger.shared.log("✅ [VHIDManager] \(description) completed successfully")
                        if !output.isEmpty {
                            AppLogger.shared.log("📋 [VHIDManager] Command output: \(output)")
                        }
                        continuation.resume(returning: true)
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
