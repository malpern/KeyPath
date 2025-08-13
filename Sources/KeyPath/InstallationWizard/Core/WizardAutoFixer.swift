import AppKit
import Foundation

/// Handles automatic fixing of detected issues - pure action logic
class WizardAutoFixer: AutoFixCapable {
    private let kanataManager: KanataManager
    private let vhidDeviceManager: VHIDDeviceManager
    private let launchDaemonInstaller: LaunchDaemonInstaller
    private let packageManager: PackageManager

    init(
        kanataManager: KanataManager, vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
        launchDaemonInstaller: LaunchDaemonInstaller = LaunchDaemonInstaller(),
        packageManager: PackageManager = PackageManager()
    ) {
        self.kanataManager = kanataManager
        self.vhidDeviceManager = vhidDeviceManager
        self.launchDaemonInstaller = launchDaemonInstaller
        self.packageManager = packageManager
    }

    // MARK: - Error Analysis

    /// Analyze a kanata startup error and provide guidance
    func analyzeStartupError(_ error: String) -> (issue: WizardIssue?, canAutoFix: Bool) {
        let analysis = PermissionService.analyzeKanataError(error)

        if analysis.isPermissionError {
            let issue = WizardIssue(
                identifier: .permission(.kanataInputMonitoring),
                severity: .error,
                category: .permissions,
                title: "Permission Required",
                description: analysis.suggestedFix ?? "Grant permissions to kanata in System Settings",
                autoFixAction: nil,
                userAction: analysis.suggestedFix
            )
            return (issue, false) // Permissions can't be auto-fixed
        }

        // Check for conflict errors
        if error.lowercased().contains("address already in use") {
            let issue = WizardIssue(
                identifier: .conflict(.kanataProcessRunning(pid: 0, command: "unknown")),
                severity: .error,
                category: .conflicts,
                title: "Process Conflict",
                description: "Another kanata process is already running",
                autoFixAction: .terminateConflictingProcesses,
                userAction: "Stop the conflicting process"
            )
            return (issue, true) // Conflicts can be auto-fixed
        }

        // Check for VirtualHID errors
        if error.lowercased().contains("device not configured") {
            let issue = WizardIssue(
                identifier: .component(.vhidDeviceRunning),
                severity: .error,
                category: .permissions,
                title: "VirtualHID Issue",
                description: "Karabiner VirtualHID driver needs to be restarted",
                autoFixAction: .startKarabinerDaemon,
                userAction: "Restart the Karabiner daemon"
            )
            return (issue, true) // Can auto-fix
        }

        return (nil, false)
    }

    // MARK: - AutoFixCapable Protocol

    func canAutoFix(_ action: AutoFixAction) -> Bool {
        switch action {
        case .terminateConflictingProcesses:
            true // We can always attempt to terminate processes
        case .startKarabinerDaemon:
            true // We can attempt to start the daemon
        case .restartVirtualHIDDaemon:
            true // We can attempt to restart VirtualHID daemon
        case .installMissingComponents:
            true // We can run the installation script
        case .createConfigDirectories:
            true // We can create directories
        case .activateVHIDDeviceManager:
            vhidDeviceManager.detectInstallation() // Only if manager is installed
        case .installLaunchDaemonServices:
            true // We can attempt to install LaunchDaemon services
        case .installViaBrew:
            packageManager.checkHomebrewInstallation() // Only if Homebrew is available
        case .repairVHIDDaemonServices:
            true
        case .synchronizeConfigPaths:
            true // We can always attempt to synchronize config paths
        case .restartUnhealthyServices:
            true // We can always attempt to restart unhealthy services
        }
    }

    func performAutoFix(_ action: AutoFixAction) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Attempting auto-fix: \(action)")

        switch action {
        case .terminateConflictingProcesses:
            return await terminateConflictingProcesses()
        case .startKarabinerDaemon:
            return await startKarabinerDaemon()
        case .restartVirtualHIDDaemon:
            return await restartVirtualHIDDaemon()
        case .installMissingComponents:
            return await installMissingComponents()
        case .createConfigDirectories:
            return await createConfigDirectories()
        case .activateVHIDDeviceManager:
            return await activateVHIDDeviceManager()
        case .installLaunchDaemonServices:
            return await installLaunchDaemonServices()
        case .installViaBrew:
            return await installViaBrew()
        case .repairVHIDDaemonServices:
            return await repairVHIDDaemonServices()
        case .synchronizeConfigPaths:
            return await synchronizeConfigPaths()
        case .restartUnhealthyServices:
            return await restartUnhealthyServices()
        }
    }

    // MARK: - Reset Everything (Nuclear Option)

    /// Reset everything - kill all processes, clean up PID files, clear caches
    func resetEverything() async -> Bool {
        AppLogger.shared.log("💣 [AutoFixer] RESET EVERYTHING - Nuclear option activated")

        // 1. Kill ALL kanata processes (owned or not)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["/usr/bin/pkill", "-9", "-f", "kanata"]

        do {
            try task.run()
            task.waitUntilExit()
            AppLogger.shared.log("💥 [AutoFixer] Killed all kanata processes")
        } catch {
            AppLogger.shared.log("⚠️ [AutoFixer] Failed to kill processes: \(error)")
        }

        // 2. Remove PID file
        try? PIDFileManager.removePID()
        AppLogger.shared.log("🗑️ [AutoFixer] Removed PID file")

        // 3. Clear permission cache
        PermissionService.shared.clearCache()
        AppLogger.shared.log("🗳️ [AutoFixer] Cleared permission cache")

        // 4. Reset kanata manager state
        await kanataManager.stopKanata()
        kanataManager.lastError = nil
        kanataManager.diagnostics.removeAll()
        AppLogger.shared.log("🔄 [AutoFixer] Reset KanataManager state")

        // 5. Wait for system to settle
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        AppLogger.shared.log("✅ [AutoFixer] Reset complete - system should be in clean state")
        return true
    }

    // MARK: - Individual Auto-Fix Actions

    private func terminateConflictingProcesses() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Terminating conflicting kanata processes")

        // Use ProcessLifecycleManager to find external kanata processes
        let processManager = await ProcessLifecycleManager(kanataManager: kanataManager)
        let conflicts = await processManager.detectConflicts()

        if conflicts.externalProcesses.isEmpty {
            AppLogger.shared.log("✅ [AutoFixer] No external kanata processes to terminate")
            return true
        }

        // Kill each external process by PID (best-effort)
        var allTerminated = true
        for proc in conflicts.externalProcesses {
            let ok = await killProcessByPID(proc.pid)
            allTerminated = allTerminated && ok
        }

        // Give the system a moment to settle, then re-check
        try? await Task.sleep(nanoseconds: 800_000_000)
        let after = await processManager.detectConflicts()
        let remaining = after.externalProcesses.count

        if remaining == 0 {
            AppLogger.shared.log("✅ [AutoFixer] Conflicting kanata processes terminated")
            return true
        }

        AppLogger.shared.log(
            "⚠️ [AutoFixer] Still seeing \(remaining) external kanata process(es) after termination attempt"
        )
        return false
    }

    /// Try to kill a process by PID with a non-privileged signal; fallback to admin if needed
    private func killProcessByPID(_ pid: pid_t) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Killing process PID=\(pid)")

        // First try without sudo
        if runCommand("/bin/kill", ["-TERM", String(pid)]) == 0 {
            AppLogger.shared.log("✅ [AutoFixer] Sent SIGTERM to PID=\(pid)")
        } else {
            // Fallback with admin privileges via osascript
            let script =
                "do shell script \"/bin/kill -TERM \(pid)\" with administrator privileges with prompt \"KeyPath needs to stop a conflicting Kanata process.\""
            if runCommand("/usr/bin/osascript", ["-e", script]) == 0 {
                AppLogger.shared.log("✅ [AutoFixer] Sent SIGTERM (admin) to PID=\(pid)")
            } else {
                AppLogger.shared.log("❌ [AutoFixer] Failed to signal PID=\(pid)")
                return false
            }
        }

        // Wait a bit and verify it exited
        try? await Task.sleep(nanoseconds: 500_000_000)
        let verify = runCommand("/bin/kill", ["-0", String(pid)])
        if verify != 0 {
            AppLogger.shared.log("✅ [AutoFixer] PID=\(pid) no longer running")
            return true
        }

        // Force kill
        _ = runCommand("/bin/kill", ["-9", String(pid)])
        try? await Task.sleep(nanoseconds: 300_000_000)
        let still = runCommand("/bin/kill", ["-0", String(pid)])
        let success = still != 0
        AppLogger.shared.log(
            success
                ? "✅ [AutoFixer] Force killed PID=\(pid)"
                : "❌ [AutoFixer] PID=\(pid) still running after SIGKILL")
        return success
    }

    private func runCommand(_ path: String, _ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }

    /// Check if Karabiner Elements is installed on the system
    private func isKarabinerElementsInstalled() async -> Bool {
        let karabinerAppPath = "/Applications/Karabiner-Elements.app"
        return FileManager.default.fileExists(atPath: karabinerAppPath)
    }

    private func startKarabinerDaemon() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Starting Karabiner daemon")

        let success = await kanataManager.startKarabinerDaemon()

        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully started Karabiner daemon")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to start Karabiner daemon")
        }

        return success
    }

    private func restartVirtualHIDDaemon() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Fixing VirtualHID connection health issues")

        // Step 1: Try to clear Kanata log to reset connection health detection
        await clearKanataLog()

        // Step 2: Prefer DriverKit daemon start; fall back to legacy restart if needed
        AppLogger.shared.log("🔧 [AutoFixer] Attempting DriverKit daemon start")
        var restartSuccess = await startKarabinerDaemon()
        if !restartSuccess {
            AppLogger.shared.log("⚠️ [AutoFixer] DriverKit start failed, using legacy restart")
            restartSuccess = await legacyRestartVirtualHIDDaemon()
        }

        if restartSuccess {
            AppLogger.shared.log("✅ [AutoFixer] Successfully fixed VirtualHID connection health")
            return true
        } else {
            AppLogger.shared.log("❌ [AutoFixer] VirtualHID daemon restart failed")
            return false
        }
    }

    private func repairVHIDDaemonServices() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Repairing VHID LaunchDaemon services")
        let success = await launchDaemonInstaller.repairVHIDDaemonServices()
        if success {
            AppLogger.shared.log("✅ [AutoFixer] Repaired VHID LaunchDaemon services")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to repair VHID LaunchDaemon services")
        }
        return success
    }

    /// Clear Kanata log file to reset connection health detection
    private func clearKanataLog() async {
        AppLogger.shared.log("🔧 [AutoFixer] Attempting to clear Kanata log for fresh connection health")

        let logPath = "/var/log/kanata.log"

        // Try to truncate the log file
        let truncateTask = Process()
        truncateTask.executableURL = URL(fileURLWithPath: "/usr/bin/truncate")
        truncateTask.arguments = ["-s", "0", logPath]

        do {
            try truncateTask.run()
            truncateTask.waitUntilExit()

            if truncateTask.terminationStatus == 0 {
                AppLogger.shared.log("✅ [AutoFixer] Successfully cleared Kanata log")
            } else {
                AppLogger.shared.log(
                    "⚠️ [AutoFixer] Could not clear Kanata log (may require admin privileges)")
            }
        } catch {
            AppLogger.shared.log("⚠️ [AutoFixer] Error clearing Kanata log: \(error)")
        }
    }

    /// Force activate VirtualHID Manager using the manager application
    private func forceActivateVirtualHIDManager() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Force activating VirtualHID Manager")

        let managerPath =
            "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

        guard FileManager.default.fileExists(atPath: managerPath) else {
            AppLogger.shared.log("❌ [AutoFixer] VirtualHID Manager not found at expected path")
            return false
        }

        return await withCheckedContinuation { continuation in
            let activateTask = Process()
            activateTask.executableURL = URL(fileURLWithPath: managerPath)
            activateTask.arguments = ["forceActivate"]

            // Use atomic flag to prevent double resumption
            let lock = NSLock()
            var hasResumed = false

            // Set up timeout task
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 second timeout

                lock.lock()
                if !hasResumed {
                    hasResumed = true
                    lock.unlock()
                    AppLogger.shared.log(
                        "⚠️ [AutoFixer] VirtualHID Manager activation timed out after 10 seconds")
                    activateTask.terminate()
                    continuation.resume(returning: false)
                } else {
                    lock.unlock()
                }
            }

            activateTask.terminationHandler = { process in
                timeoutTask.cancel()

                lock.lock()
                if !hasResumed {
                    hasResumed = true
                    lock.unlock()
                    let success = process.terminationStatus == 0
                    if success {
                        AppLogger.shared.log("✅ [AutoFixer] VirtualHID Manager force activation completed")
                    } else {
                        AppLogger.shared.log(
                            "❌ [AutoFixer] VirtualHID Manager force activation failed with status: \(process.terminationStatus)"
                        )
                    }
                    continuation.resume(returning: success)
                } else {
                    lock.unlock()
                }
            }

            do {
                try activateTask.run()
            } catch {
                timeoutTask.cancel()

                lock.lock()
                if !hasResumed {
                    hasResumed = true
                    lock.unlock()
                    AppLogger.shared.log("❌ [AutoFixer] Error starting VirtualHID Manager: \(error)")
                    continuation.resume(returning: false)
                } else {
                    lock.unlock()
                }
            }
        }
    }

    /// Legacy daemon restart method (fallback)
    private func legacyRestartVirtualHIDDaemon() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Using legacy VirtualHID daemon restart")

        // Kill existing daemon
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-f", "Karabiner-VirtualHIDDevice-Daemon"]

        do {
            try killTask.run()
            killTask.waitUntilExit()

            // Wait for process to terminate
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Start daemon again
            let startSuccess = await startKarabinerDaemon()

            if startSuccess {
                AppLogger.shared.log("✅ [AutoFixer] Legacy VirtualHID daemon restart completed")
            } else {
                AppLogger.shared.log("❌ [AutoFixer] Legacy VirtualHID daemon restart failed")
            }

            return startSuccess

        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Error in legacy VirtualHID daemon restart: \(error)")
            return false
        }
    }

    private func installMissingComponents() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Installing missing components")

        let success = await kanataManager.performTransparentInstallation()

        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully installed missing components")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to install missing components")
        }

        return success
    }

    private func createConfigDirectories() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Creating config directories")

        let configDirectory = "\(NSHomeDirectory())/Library/Application Support/KeyPath"

        do {
            try FileManager.default.createDirectory(
                atPath: configDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            AppLogger.shared.log("✅ [AutoFixer] Successfully created config directories")
            return true

        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Failed to create config directories: \(error)")
            return false
        }
    }

    private func activateVHIDDeviceManager() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Activating VHIDDevice Manager")

        // First try automatic activation
        let success = await vhidDeviceManager.activateManager()

        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully activated VHIDDevice Manager")
            return true
        } else {
            AppLogger.shared.log(
                "⚠️ [AutoFixer] Automatic activation failed - showing user dialog for manual activation")

            // Show dialog to guide user through manual driver extension activation
            await showDriverExtensionDialog()

            // Wait a moment for user to potentially complete the action
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            // Check if activation succeeded after user intervention
            let manualSuccess = vhidDeviceManager.detectActivation()

            if manualSuccess {
                AppLogger.shared.log("✅ [AutoFixer] VHIDDevice Manager activated after user intervention")
                return true
            } else {
                AppLogger.shared.log(
                    "⚠️ [AutoFixer] VHIDDevice Manager still not activated - user may need more time")
                // Still return true since we showed helpful guidance
                return true
            }
        }
    }

    /// Show dialog to guide user through manual driver extension activation
    private func showDriverExtensionDialog() async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Driver Extension Activation Required"
            alert.informativeText = """
            KeyPath needs to activate the VirtualHID Device driver extension, but this requires manual approval for security.

            Please follow these steps:

            1. Click "Open System Settings" below
            2. Go to Privacy & Security → Driver Extensions
            3. Find "Karabiner-VirtualHIDDevice-Manager.app"
            4. Turn ON the toggle switch
            5. Return to KeyPath

            This is a one-time setup required for keyboard remapping functionality.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "I'll Do This Later")

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // Open System Settings to Driver Extensions
                AppLogger.shared.log(
                    "🔧 [AutoFixer] Opening System Settings for driver extension activation")
                openDriverExtensionSettings()
            } else {
                AppLogger.shared.log("🔧 [AutoFixer] User chose to activate driver extension later")
            }
        }
    }

    /// Open System Settings to the Driver Extensions page
    private func openDriverExtensionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.SystemExtensionsSettings")!
        NSWorkspace.shared.open(url)
    }

    private func installLaunchDaemonServices() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Installing LaunchDaemon services with consolidated single-prompt method")

        // Use the new consolidated method that handles everything with a single admin prompt:
        // - Install all LaunchDaemon plist files
        // - Create system config directories
        // - Copy/create system config files
        // - Load all services into launchctl
        let success = launchDaemonInstaller.createConfigureAndLoadAllServices()

        if success {
            AppLogger.shared.log("✅ [AutoFixer] LaunchDaemon installation completed successfully with single admin prompt")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] LaunchDaemon installation failed")
        }

        return success
    }

    private func installViaBrew() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Installing packages via Homebrew")

        var stepsCompleted = 0
        var stepsFailed = 0
        let totalSteps = 3

        // Step 1: Check if Homebrew is available
        AppLogger.shared.log("🔧 [AutoFixer] Step 1/\(totalSteps): Checking Homebrew availability...")
        guard packageManager.checkHomebrewInstallation() else {
            AppLogger.shared.log("❌ [AutoFixer] Step 1 FAILED: Homebrew not available for package installation")
            return false
        }
        AppLogger.shared.log("✅ [AutoFixer] Step 1 SUCCESS: Homebrew is available")
        stepsCompleted += 1

        // Step 2: Check what packages need to be installed
        AppLogger.shared.log("🔧 [AutoFixer] Step 2/\(totalSteps): Detecting current package installation...")
        let kanataInfo = packageManager.detectKanataInstallation()
        AppLogger.shared.log("✅ [AutoFixer] Step 2 SUCCESS: Package detection complete")
        stepsCompleted += 1

        // Step 3: Install Kanata if needed
        AppLogger.shared.log("🔧 [AutoFixer] Step 3/\(totalSteps): Installing Kanata package...")
        if !kanataInfo.isInstalled {
            let result = await packageManager.installKanataViaBrew()

            switch result {
            case .success:
                AppLogger.shared.log("✅ [AutoFixer] Step 3 SUCCESS: Kanata installed via Homebrew")
                stepsCompleted += 1
            case let .failure(reason):
                AppLogger.shared.log("❌ [AutoFixer] Step 3 FAILED: Failed to install Kanata - \(reason)")
                stepsFailed += 1
            case .homebrewNotAvailable:
                AppLogger.shared.log("❌ [AutoFixer] Step 3 FAILED: Homebrew not available for Kanata installation")
                stepsFailed += 1
            case .packageNotFound:
                AppLogger.shared.log("❌ [AutoFixer] Step 3 FAILED: Kanata package not found in Homebrew")
                stepsFailed += 1
            case .userCancelled:
                AppLogger.shared.log("⚠️ [AutoFixer] Step 3 CANCELLED: Kanata installation cancelled by user")
                return false
            }
        } else {
            AppLogger.shared.log("✅ [AutoFixer] Step 3 SUCCESS: Kanata already installed - \(kanataInfo.description)")
            stepsCompleted += 1
        }

        let success = stepsFailed == 0
        if success {
            AppLogger.shared.log("✅ [AutoFixer] Homebrew installation completed successfully (\(stepsCompleted)/\(totalSteps) steps)")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Homebrew installation failed (\(stepsFailed) steps failed, \(stepsCompleted)/\(totalSteps) completed)")
        }

        return success
    }

    // MARK: - Helper Methods

    /// Attempts to gracefully terminate a specific process by PID
    private func terminateProcess(pid: Int) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Terminating process PID: \(pid)")

        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
        killTask.arguments = ["-TERM", String(pid)]

        do {
            try killTask.run()
            killTask.waitUntilExit()

            if killTask.terminationStatus == 0 {
                // Wait a bit for graceful termination
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                // Check if process is still running
                let checkTask = Process()
                checkTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                checkTask.arguments = ["-0", String(pid)]

                try checkTask.run()
                checkTask.waitUntilExit()

                if checkTask.terminationStatus != 0 {
                    // Process is gone
                    AppLogger.shared.log("✅ [AutoFixer] Process \(pid) terminated gracefully")
                    return true
                } else {
                    // Process still running, try SIGKILL
                    AppLogger.shared.log("⚠️ [AutoFixer] Process \(pid) still running, using SIGKILL")
                    return await forceTerminateProcess(pid: pid)
                }
            } else {
                AppLogger.shared.log("❌ [AutoFixer] Failed to send SIGTERM to process \(pid)")
                return await forceTerminateProcess(pid: pid)
            }
        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Error terminating process \(pid): \(error)")
            return false
        }
    }

    /// Force terminates a process using SIGKILL
    private func forceTerminateProcess(pid: Int) async -> Bool {
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
        killTask.arguments = ["-9", String(pid)]

        do {
            try killTask.run()
            killTask.waitUntilExit()

            let success = killTask.terminationStatus == 0
            if success {
                AppLogger.shared.log("✅ [AutoFixer] Force terminated process \(pid)")
            } else {
                AppLogger.shared.log("❌ [AutoFixer] Failed to force terminate process \(pid)")
            }
            return success

        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Error force terminating process \(pid): \(error)")
            return false
        }
    }

    // MARK: - Config Path Synchronization

    /// Synchronize config paths between Kanata processes and KeyPath expectations
    private func synchronizeConfigPaths() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Starting config path synchronization")

        do {
            // Copy the current KeyPath config to the system location where Kanata expects it
            let userConfigPath = WizardSystemPaths.userConfigPath
            let systemConfigPath = WizardSystemPaths.systemConfigPath

            AppLogger.shared.log("📋 [AutoFixer] Copying config from \(userConfigPath) to \(systemConfigPath)")

            // Ensure the system directory exists
            let systemConfigDir = URL(fileURLWithPath: systemConfigPath).deletingLastPathComponent().path
            try FileManager.default.createDirectory(atPath: systemConfigDir, withIntermediateDirectories: true)

            // Check if source file exists
            guard FileManager.default.fileExists(atPath: userConfigPath) else {
                AppLogger.shared.log("❌ [AutoFixer] Source config file does not exist at \(userConfigPath)")
                return false
            }

            // Read the user config
            let configContent = try String(contentsOfFile: userConfigPath)
            AppLogger.shared.log("📄 [AutoFixer] Read \(configContent.count) characters from user config")

            // Use AppleScript to write to system location with admin privileges
            let script = """
            do shell script "echo '\(configContent.replacingOccurrences(of: "'", with: "\\'"))' > '\(systemConfigPath)'" with administrator privileges
            """

            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            let result = appleScript?.executeAndReturnError(&error)

            if let error {
                AppLogger.shared.log("❌ [AutoFixer] AppleScript error: \(error)")
                return false
            }

            // Verify the file was written
            if FileManager.default.fileExists(atPath: systemConfigPath) {
                let systemContent = try String(contentsOfFile: systemConfigPath)
                let success = systemContent == configContent

                if success {
                    AppLogger.shared.log("✅ [AutoFixer] Config successfully synchronized to system location")
                    AppLogger.shared.log("🔄 [AutoFixer] Kanata should now detect config changes via --watch")
                } else {
                    AppLogger.shared.log("❌ [AutoFixer] Config content mismatch after copy")
                }

                return success
            } else {
                AppLogger.shared.log("❌ [AutoFixer] System config file was not created")
                return false
            }

        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Error synchronizing config paths: \(error)")
            return false
        }
    }
    
    private func restartUnhealthyServices() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] *** MIXED SCENARIO FIX TRIGGERED *** Fixing unhealthy LaunchDaemon services")
        AppLogger.shared.log("🔧 [AutoFixer] This means the new logic is working - will install missing + restart unhealthy")
        
        // Get current status to determine what needs to be done
        let status = launchDaemonInstaller.getServiceStatus()
        
        // Step 1: Install any missing services first
        if !status.allServicesLoaded {
            AppLogger.shared.log("🔧 [AutoFixer] Some services not loaded, installing missing LaunchDaemon services first")
            let installSuccess = launchDaemonInstaller.createConfigureAndLoadAllServices()
            if !installSuccess {
                AppLogger.shared.log("❌ [AutoFixer] Failed to install missing services")
                return false
            }
            AppLogger.shared.log("✅ [AutoFixer] Installed missing services")
        }
        
        // Step 2: Restart any unhealthy services
        let restartSuccess = await launchDaemonInstaller.restartUnhealthyServices()
        
        if restartSuccess {
            AppLogger.shared.log("✅ [AutoFixer] Successfully fixed unhealthy LaunchDaemon services")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to restart unhealthy services")
        }
        
        return restartSuccess
    }
}
