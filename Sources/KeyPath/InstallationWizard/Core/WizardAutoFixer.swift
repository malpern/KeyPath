import AppKit
import Foundation
import os
import SwiftUI

/// Handles automatic fixing of detected issues - pure action logic
class WizardAutoFixer: AutoFixCapable {
    private let kanataManager: KanataManager
    private let vhidDeviceManager: VHIDDeviceManager
    private let launchDaemonInstaller: LaunchDaemonInstaller
    private let packageManager: PackageManager
    private let bundledKanataManager: BundledKanataManager
    // REMOVED: toastManager was unused and created architecture violation (Core → UI dependency)
    private let autoFixSync = ProcessSynchronizationActor()

    @MainActor init(
        kanataManager: KanataManager,
        vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
        launchDaemonInstaller: LaunchDaemonInstaller = LaunchDaemonInstaller(),
        packageManager: PackageManager = PackageManager(),
        bundledKanataManager: BundledKanataManager = BundledKanataManager()
    ) {
        self.kanataManager = kanataManager
        self.vhidDeviceManager = vhidDeviceManager
        self.launchDaemonInstaller = launchDaemonInstaller
        self.packageManager = packageManager
        self.bundledKanataManager = bundledKanataManager
    }

    

    // MARK: - Error Analysis

    /// Analyze a kanata startup error and provide guidance
    @MainActor func analyzeStartupError(_ error: String) -> (issue: WizardIssue?, canAutoFix: Bool) {
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
        case .installBundledKanata:
            true // We can always install bundled kanata binary
        case .repairVHIDDaemonServices:
            true
        case .synchronizeConfigPaths:
            true // We can always attempt to synchronize config paths
        case .restartUnhealthyServices:
            true // We can always attempt to restart unhealthy services
        case .adoptOrphanedProcess:
            true // We can always attempt to adopt an orphaned process
        case .replaceOrphanedProcess:
            true // We can always attempt to replace an orphaned process
        case .installLogRotation:
            true // We can always attempt to install log rotation
        case .replaceKanataWithBundled:
            true // We can always attempt to replace kanata with bundled version
        case .enableTCPServer:
            true // We can always attempt to enable TCP server
        case .setupTCPAuthentication:
            true // We can always attempt to setup TCP authentication
        case .regenerateCommServiceConfiguration:
            true // We can always attempt to regenerate communication service configuration
        case .restartCommServer:
            true // We can always attempt to restart communication server
        case .fixDriverVersionMismatch:
            // Can fix if driver is missing OR has wrong version
            !vhidDeviceManager.detectInstallation() || vhidDeviceManager.hasVersionMismatch()
        }
    }

    func performAutoFix(_ action: AutoFixAction) async -> Bool {
        _ = await autoFixSync.synchronize {
            // Synchronize using the actor, but call into self outside the Sendable closure
            true
        }
        // Execute the actual work outside the synchronize closure to avoid Sendable capture of self
        return await _performAutoFix(action)
    }

    private func _performAutoFix(_ action: AutoFixAction) async -> Bool {
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
        case .installBundledKanata:
            return await installBundledKanata()
        case .repairVHIDDaemonServices:
            return await repairVHIDDaemonServices()
        case .synchronizeConfigPaths:
            return await synchronizeConfigPaths()
        case .restartUnhealthyServices:
            return await restartUnhealthyServices()
        case .adoptOrphanedProcess:
            return await adoptOrphanedProcess()
        case .replaceOrphanedProcess:
            return await replaceOrphanedProcess()
        case .installLogRotation:
            return await installLogRotation()
        case .replaceKanataWithBundled:
            return await replaceKanataWithBundled()
        case .enableTCPServer:
            return await enableTCPServer()
        case .setupTCPAuthentication:
            return await setupTCPAuthentication()
        case .regenerateCommServiceConfiguration:
            return await regenerateCommServiceConfiguration()
        case .restartCommServer:
            return await restartCommServer()
        case .fixDriverVersionMismatch:
            return await fixDriverVersionMismatch()
        }
    }

    // MARK: - Driver Version Management

    private func fixDriverVersionMismatch() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Fixing driver installation/version")

        let driverInstalled = vhidDeviceManager.detectInstallation()

        // Only show confirmation dialog if driver is installed (version mismatch scenario)
        // If driver is missing, assume caller (wizard) already showed confirmation
        if driverInstalled {
            // Show dialog explaining the version downgrade
            guard let versionMessage = vhidDeviceManager.getVersionMismatchMessage() else {
                AppLogger.shared.log("⚠️ [AutoFixer] Driver installed but no version mismatch message available")
                return false
            }

            // Show user-facing dialog on main thread
            let userConfirmed = await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Karabiner Driver Version Fix Required"
                alert.informativeText = versionMessage
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Download & Install v5.0.0")
                alert.addButton(withTitle: "Cancel")

                let response = alert.runModal()
                return response == .alertFirstButtonReturn
            }

            guard userConfirmed else {
                AppLogger.shared.log("ℹ️ [AutoFixer] User cancelled driver version fix")
                return false
            }
        } else {
            AppLogger.shared.log("🔧 [AutoFixer] Driver not installed - proceeding with installation (confirmation assumed from caller)")
        }

        // Download and install the correct version
        let success = await vhidDeviceManager.downloadAndInstallCorrectVersion()

        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully fixed driver version mismatch")

            // Kill old VirtualHID processes first
            AppLogger.shared.log("🔄 [AutoFixer] Stopping old VirtualHID processes...")
            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            killTask.arguments = ["/usr/bin/pkill", "-9", "Karabiner-VirtualHIDDevice"]
            try? killTask.run()
            killTask.waitUntilExit()

            // Activate the manager to register the new driver extension with macOS
            AppLogger.shared.log("🚀 [AutoFixer] Activating manager to register v5.0.0 system extension...")
            let activationSuccess = await vhidDeviceManager.activateManager()
            if activationSuccess {
                AppLogger.shared.log("✅ [AutoFixer] Manager activation succeeded - v5.0.0 should be registered")
            } else {
                AppLogger.shared.log("⚠️ [AutoFixer] Manager activation failed or timed out - may need manual activation")
            }

            // Show success message
            // TODO: Re-enable driver installation guide when DriverInstallationGuideView is available
            /* await MainActor.run {
                let guideView = DriverInstallationGuideView {
                    // Open System Settings when button is clicked
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }

                let hostingController = NSHostingController(rootView: guideView)

                let window = NSWindow(contentViewController: hostingController)
                window.title = "Driver Installation Guide"
                window.styleMask = [.titled, .closable]
                window.isReleasedWhenClosed = false
                window.center()

                NSApp.runModal(for: window)
                window.close()
            } */
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to fix driver version mismatch")

            // Show error message
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText = "Failed to download or install Karabiner-DriverKit-VirtualHIDDevice v5.0.0. Please check your internet connection and try again."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }

        return success
    }

    // MARK: - Reset Everything (Nuclear Option)

    /// Reset everything - kill all processes, clean up PID files, clear caches
    @MainActor func resetEverything() async -> Bool {
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

        // 3. Oracle handles permission caching automatically
        AppLogger.shared.log("🔮 [AutoFixer] Oracle permission system - no manual cache clearing needed")

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
        let processManager = ProcessLifecycleManager(kanataManager: kanataManager)
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

            // Thread-safe guard using actor isolation
            let guardQueue = DispatchQueue(label: "vhid-activate-guard")
            let hasResumed = OSAllocatedUnfairLock(initialState: false)

            // Set up timeout task
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 second timeout
                guardQueue.async {
                    let shouldResume = hasResumed.withLock { resumed in
                        if !resumed {
                            resumed = true
                            return true
                        }
                        return false
                    }
                    
                    if shouldResume {
                        AppLogger.shared.log(
                            "⚠️ [AutoFixer] VirtualHID Manager activation timed out after 10 seconds")
                        activateTask.terminate()
                        continuation.resume(returning: false)
                    }
                }
            }

            activateTask.terminationHandler = { process in
                timeoutTask.cancel()
                guardQueue.async {
                    let shouldResume = hasResumed.withLock { resumed in
                        if !resumed {
                            resumed = true
                            return true
                        }
                        return false
                    }
                    
                    if shouldResume {
                        let success = process.terminationStatus == 0
                        if success {
                            AppLogger.shared.log("✅ [AutoFixer] VirtualHID Manager force activation completed")
                        } else {
                            AppLogger.shared.log(
                                "❌ [AutoFixer] VirtualHID Manager force activation failed with status: \(process.terminationStatus)")
                        }
                        continuation.resume(returning: success)
                    }
                }
            }

            do {
                try activateTask.run()
            } catch {
                timeoutTask.cancel()
                guardQueue.async {
                    let shouldResume = hasResumed.withLock { resumed in
                        if !resumed {
                            resumed = true
                            return true
                        }
                        return false
                    }
                    
                    if shouldResume {
                        AppLogger.shared.log("❌ [AutoFixer] Error starting VirtualHID Manager: \(error)")
                        continuation.resume(returning: false)
                    }
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
            if TestEnvironment.isRunningTests {
                AppLogger.shared.log("🧪 [AutoFixer] Suppressing driver extension dialog in test environment")
            } else {
                await showDriverExtensionDialog()
            }

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
            KeyPath has installed the VirtualHID Device driver (v5.0.0), but it needs your approval to activate.

            Please follow these steps:

            1. Click "Open System Settings" below
            2. In the Driver Extensions section, find "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"
            3. If you see multiple versions, make sure to enable version 5.0.0
            4. Turn ON the toggle switch (you may need to approve in a popup)
            5. Return to KeyPath and close the wizard

            NOTE: If you see an older version (like 1.8.0), you can disable it - we only need v5.0.0.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "I'll Do This Later")

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                // Open System Settings to Driver Extensions category (macOS 15+)
                AppLogger.shared.log(
                    "🔧 [AutoFixer] Opening System Settings Driver Extensions category")
                let url = URL(string: WizardSystemPaths.driverExtensionsCategory)!
                NSWorkspace.shared.open(url)
            } else {
                AppLogger.shared.log("🔧 [AutoFixer] User chose to activate driver extension later")
            }
        }
    }

    /// Open System Settings to the Driver Extensions category (macOS 15+)
    private func openDriverExtensionSettings() {
        let url = URL(string: WizardSystemPaths.driverExtensionsCategory)!
        NSWorkspace.shared.open(url)
    }

    private func installLaunchDaemonServices() async -> Bool {
        AppLogger.shared.log(
            "🔧 [AutoFixer] *** ENTRY POINT *** installLaunchDaemonServices() called")
        AppLogger.shared.log(
            "🔧 [AutoFixer] Installing LaunchDaemon services with consolidated single-prompt method")
        AppLogger.shared.log("🔧 [AutoFixer] About to call launchDaemonInstaller.createConfigureAndLoadAllServices()")

        // Use the new consolidated method that handles everything with a single admin prompt:
        // - Install all LaunchDaemon plist files
        // - Create system config directories
        // - Copy/create system config files
        // - Load all services into launchctl
        AppLogger.shared.log("🔧 [AutoFixer] Calling createConfigureAndLoadAllServices() now...")
        let installer1 = launchDaemonInstaller
        let success = await MainActor.run { installer1.createConfigureAndLoadAllServices() }
        AppLogger.shared.log("🔧 [AutoFixer] createConfigureAndLoadAllServices() returned: \(success)")

        if success {
            AppLogger.shared.log(
                "✅ [AutoFixer] LaunchDaemon installation completed successfully with single admin prompt")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] LaunchDaemon installation failed")
        }

        return success
    }

    private func installBundledKanata() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Installing bundled kanata binary to system location")

        let totalSteps = 2
        var stepsCompleted = 0

        // Step 1: Check if bundled binary is available and properly signed
        AppLogger.shared.log("🔧 [AutoFixer] Step 1/\(totalSteps): Verifying bundled kanata binary...")
        let bundledManager = await BundledKanataManager()
        let signingStatus = await bundledManager.bundledKanataSigningStatus()
        
        guard signingStatus.isDeveloperID else {
            AppLogger.shared.log("❌ [AutoFixer] Step 1 FAILED: Bundled kanata binary is not properly signed: \(signingStatus)")
            return false
        }
        AppLogger.shared.log("✅ [AutoFixer] Step 1 SUCCESS: Bundled kanata binary is properly signed")
        stepsCompleted += 1

        // Step 2: Install bundled binary to system location
        AppLogger.shared.log("🔧 [AutoFixer] Step 2/\(totalSteps): Installing bundled binary to system location...")
        let installSuccess = await bundledManager.replaceBinaryWithBundled()
        
        if installSuccess {
            stepsCompleted += 1
            AppLogger.shared.log("✅ [AutoFixer] Step 2 SUCCESS: Bundled kanata binary installed successfully")

        } else {
            AppLogger.shared.log("❌ [AutoFixer] Step 2 FAILED: Failed to install bundled kanata binary")
            return false
        }

        AppLogger.shared.log(
            "✅ [AutoFixer] Bundled kanata installation completed successfully (\(stepsCompleted)/\(totalSteps) steps)"
        )
        return true
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

            AppLogger.shared.log(
                "📋 [AutoFixer] Copying config from \(userConfigPath) to \(systemConfigPath)")

            // Ensure the system directory exists
            let systemConfigDir = URL(fileURLWithPath: systemConfigPath).deletingLastPathComponent().path
            try FileManager.default.createDirectory(
                atPath: systemConfigDir, withIntermediateDirectories: true
            )

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
            _ = appleScript?.executeAndReturnError(&error)

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
                    AppLogger.shared.log("🔄 [AutoFixer] Config synchronized - changes will be applied via TCP reload commands")
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
        AppLogger.shared.log(
            "🔧 [AutoFixer] restartUnhealthyServices() called")
        AppLogger.shared.log("🔧 [AutoFixer] Timestamp: \(Date())")
        AppLogger.shared.log("🔧 [AutoFixer] OnMainActor: true")
        AppLogger.shared.log(
            "🔧 [AutoFixer] This means the new logic is working - will install missing + restart unhealthy"
        )

        // Get current status to determine what needs to be done
        AppLogger.shared.log("🔧 [AutoFixer] Step 1: Getting current service status...")
        let installer2 = launchDaemonInstaller
        let status = await MainActor.run { installer2.getServiceStatus() }

        AppLogger.shared.log("🔧 [AutoFixer] Current status breakdown:")
        AppLogger.shared.log(
            "🔧 [AutoFixer] - Kanata loaded: \(status.kanataServiceLoaded), healthy: \(status.kanataServiceHealthy)"
        )
        AppLogger.shared.log(
            "🔧 [AutoFixer] - VHID Daemon loaded: \(status.vhidDaemonServiceLoaded), healthy: \(status.vhidDaemonServiceHealthy)"
        )
        AppLogger.shared.log(
            "🔧 [AutoFixer] - VHID Manager loaded: \(status.vhidManagerServiceLoaded), healthy: \(status.vhidManagerServiceHealthy)"
        )
        AppLogger.shared.log("🔧 [AutoFixer] - All services loaded: \(status.allServicesLoaded)")
        AppLogger.shared.log("🔧 [AutoFixer] - All services healthy: \(status.allServicesHealthy)")

        // Step 1: Install any missing services first
        if !status.allServicesLoaded {
            AppLogger.shared.log(
                "🔧 [AutoFixer] Step 2: Some services not loaded, installing missing LaunchDaemon services first"
            )
            let installer3 = launchDaemonInstaller
            let installSuccess = await MainActor.run { installer3.createConfigureAndLoadAllServices() }
            AppLogger.shared.log("🔧 [AutoFixer] Installation result: \(installSuccess)")
            if !installSuccess {
                AppLogger.shared.log("❌ [AutoFixer] Failed to install missing services")
                return false
            }
            AppLogger.shared.log("✅ [AutoFixer] Installed missing services")
        } else {
            AppLogger.shared.log(
                "🔧 [AutoFixer] Step 2: All services already loaded, skipping installation")
        }

        // Step 2: Restart any unhealthy services
        AppLogger.shared.log(
            "🔧 [AutoFixer] Step 3: Calling comprehensive restart method on LaunchDaemonInstaller")
        AppLogger.shared.log(
            "🔧 [AutoFixer] About to call: launchDaemonInstaller.restartUnhealthyServices()")

        let restartSuccess = await launchDaemonInstaller.restartUnhealthyServices()

        AppLogger.shared.log(
            "🔧 [AutoFixer] Step 4: LaunchDaemonInstaller.restartUnhealthyServices() returned: \(restartSuccess)"
        )
        AppLogger.shared.log("🔧 [AutoFixer] Checking final service status after restart...")

        let installer4 = launchDaemonInstaller
        let finalStatus = await MainActor.run { installer4.getServiceStatus() }
        AppLogger.shared.log("🔧 [AutoFixer] Final status breakdown:")
        AppLogger.shared.log(
            "🔧 [AutoFixer] - Kanata loaded: \(finalStatus.kanataServiceLoaded), healthy: \(finalStatus.kanataServiceHealthy)"
        )
        AppLogger.shared.log(
            "🔧 [AutoFixer] - VHID Daemon loaded: \(finalStatus.vhidDaemonServiceLoaded), healthy: \(finalStatus.vhidDaemonServiceHealthy)"
        )
        AppLogger.shared.log(
            "🔧 [AutoFixer] - VHID Manager loaded: \(finalStatus.vhidManagerServiceLoaded), healthy: \(finalStatus.vhidManagerServiceHealthy)"
        )
        AppLogger.shared.log("🔧 [AutoFixer] - All services healthy: \(finalStatus.allServicesHealthy)")

        if restartSuccess {
            AppLogger.shared.log("✅ [AutoFixer] Successfully fixed unhealthy LaunchDaemon services")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to fix unhealthy services - analyzing cause...")
            AppLogger.shared.log("❌ [AutoFixer] This usually means:")
            AppLogger.shared.log("❌ [AutoFixer] 1. Admin password was not provided when prompted")
            AppLogger.shared.log("❌ [AutoFixer] 2. Missing services installation failed")
            AppLogger.shared.log("❌ [AutoFixer] 3. launchctl restart commands were denied by system")
            AppLogger.shared.log(
                "❌ [AutoFixer] 4. Services restarted but are still unhealthy (permission/config issues)")
            AppLogger.shared.log(
                "💡 [AutoFixer] SOLUTION: Try the Fix button again and provide admin password when prompted")
        }

        AppLogger.shared.log(
            "🔧 [AutoFixer] restartUnhealthyServices() complete - returning: \(restartSuccess)")
        return restartSuccess
    }

    // MARK: - Orphaned Process Auto-Fix Actions

    /// Adopt an existing orphaned Kanata process by installing LaunchDaemon management
    private func adoptOrphanedProcess() async -> Bool {
        AppLogger.shared.log("🔗 [AutoFixer] Starting orphaned process adoption")

        // Show user feedback

        // Install LaunchDaemon service files without loading/starting them (no interference with running process)
        AppLogger.shared.log("🔗 [AutoFixer] Installing LaunchDaemon service files for future management")
        let installer5 = launchDaemonInstaller
        let installSuccess = await MainActor.run { installer5.createAllLaunchDaemonServicesInstallOnly() }

        if installSuccess {
            AppLogger.shared.log("✅ [AutoFixer] Successfully adopted orphaned Kanata process")
            return true
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to adopt orphaned process")
            return false
        }
    }

    /// Replace an orphaned Kanata process with a properly managed one
    private func replaceOrphanedProcess() async -> Bool {
        AppLogger.shared.log("🔄 [AutoFixer] Starting orphaned process replacement")

        // Step 1: Kill existing process
        AppLogger.shared.log("🔄 [AutoFixer] Step 1: Terminating orphaned Kanata process")

        let terminateSuccess = await terminateConflictingProcesses()

        if !terminateSuccess {
            AppLogger.shared.log("⚠️ [AutoFixer] Warning: Failed to cleanly terminate orphaned process")
        }

        // Step 2: Install and start managed service
        AppLogger.shared.log("🔄 [AutoFixer] Step 2: Installing and starting managed Kanata service")

        let installSuccess = await installLaunchDaemonServices()

        if installSuccess {
            AppLogger.shared.log("✅ [AutoFixer] Successfully replaced orphaned process with managed service")
            return true
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to start managed service")
            return false
        }
    }

    // MARK: - Log Rotation Auto-Fix

    /// Install log rotation service to keep Kanata logs under 10MB total
    private func installLogRotation() async -> Bool {
        AppLogger.shared.log("📝 [AutoFixer] Installing log rotation service for Kanata logs")


        let installer6 = launchDaemonInstaller
        let success = await MainActor.run { installer6.installLogRotationService() }

        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully installed log rotation service")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to install log rotation service")
        }

        return success
    }

    private func replaceKanataWithBundled() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Replacing system kanata with bundled Developer ID signed version")


        let success = await bundledKanataManager.replaceBinaryWithBundled()

        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully replaced system kanata with bundled version")

            // Restart the kanata service to use the new binary
            AppLogger.shared.log("🔄 [AutoFixer] Restarting kanata service to use new binary")
            await kanataManager.restartKanata()
            AppLogger.shared.log("✅ [AutoFixer] Restarted kanata service with new binary")

            return true
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to replace kanata binary")
            return false
        }
    }

    // MARK: - TCP Communication Server Auto-Fix Actions

    private func enableTCPServer() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Enabling TCP server")

        await MainActor.run {
            PreferencesService.shared.tcpServerEnabled = true
        }

        // Restart service with TCP enabled
        return await regenerateCommServiceConfiguration()
    }

    private func setupTCPAuthentication() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Setting up TCP authentication")

        // Generate a new auth token using centralized manager
        let newToken = await TCPAuthTokenManager.generateSecureToken()

        do {
            // Update token via centralized manager
            try await TCPAuthTokenManager.setToken(newToken)

            // Also update preferences for consistency
            await MainActor.run {
                PreferencesService.shared.tcpAuthToken = newToken
            }

            // Regenerate service configuration with new token
            let regenSuccess = await regenerateCommServiceConfiguration()
            guard regenSuccess else {
                AppLogger.shared.log("❌ [AutoFixer] Failed to regenerate service configuration")
                return false
            }

            // Restart server to adopt new token
            let restartSuccess = await restartCommServer()
            guard restartSuccess else {
                AppLogger.shared.log("❌ [AutoFixer] Failed to restart communication server")
                return false
            }

            // Test the new token
            let commSnapshot = PreferencesService.communicationSnapshot()
            let client = KanataTCPClient(port: commSnapshot.tcpPort)

            if await client.authenticate(token: newToken) {
                AppLogger.shared.log("✅ [AutoFixer] TCP authentication setup successful")
                return true
            } else {
                AppLogger.shared.log("❌ [AutoFixer] TCP authentication test failed")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [AutoFixer] Failed to set token via TokenManager: \(error)")
            return false
        }
    }

    private func regenerateCommServiceConfiguration() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Regenerating communication service configuration")

        // Use the existing service configuration regeneration method
        let success = await launchDaemonInstaller.regenerateServiceWithCurrentSettings()

        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully regenerated communication service configuration")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to regenerate communication service configuration")
        }

        return success
    }

    private func restartCommServer() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Restarting communication server")

        // Use the existing unhealthy services restart method
        let success = await launchDaemonInstaller.restartUnhealthyServices()

        if success {
            AppLogger.shared.log("✅ [AutoFixer] Successfully restarted communication server")
        } else {
            AppLogger.shared.log("❌ [AutoFixer] Failed to restart communication server")
        }

        return success
    }
}
