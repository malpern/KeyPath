import AppKit
import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore
import os

/// Handles automatic fixing of detected issues - pure action logic
class WizardAutoFixer: AutoFixCapable {
    private let kanataManager: RuntimeCoordinator
    private let vhidDeviceManager: VHIDDeviceManager
    // NOTE: launchDaemonInstaller removed - health checks migrated to ServiceHealthChecker
    private let packageManager: PackageManager
    private let bundledRuntimeCoordinator: BundledRuntimeCoordinator
    // REMOVED: toastManager was unused and created architecture violation (Core → UI dependency)
    // REMOVED: ProcessSynchronizationActor - no longer needed

    @MainActor init(
        kanataManager: RuntimeCoordinator,
        vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
        packageManager: PackageManager = PackageManager(),
        bundledRuntimeCoordinator: BundledRuntimeCoordinator = BundledRuntimeCoordinator()
    ) {
        self.kanataManager = kanataManager
        self.vhidDeviceManager = vhidDeviceManager
        self.packageManager = packageManager
        self.bundledRuntimeCoordinator = bundledRuntimeCoordinator
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
        case .installPrivilegedHelper:
            true // We can always attempt to install the helper
        case .reinstallPrivilegedHelper:
            true // We can always attempt to reinstall the helper
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
            vhidDeviceManager.hasVersionMismatch() // Only if there's a version mismatch
        case .installCorrectVHIDDriver:
            true // Attempt auto-install when driver missing
        }
    }

    func performAutoFix(_ action: AutoFixAction) async -> Bool {
        // Execute directly on MainActor
        await _performAutoFix(action)
    }

    private func _performAutoFix(_ action: AutoFixAction) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Attempting auto-fix: \(action)")

        switch action {
        case .installPrivilegedHelper:
            return await installPrivilegedHelper()
        case .reinstallPrivilegedHelper:
            return await reinstallPrivilegedHelper()
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
        case .installCorrectVHIDDriver:
            return await installCorrectVHIDDriver()
        }
    }

    // MARK: - Privileged Helper Management

    private func installPrivilegedHelper() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Installing privileged helper")

        do {
            try await HelperManager.shared.installHelper()
            AppLogger.shared.info("✅ [AutoFixer] Privileged helper installed successfully")
            return true
        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Failed to install helper: \(error)")
            return false
        }
    }

    private func reinstallPrivilegedHelper() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Reinstalling privileged helper")

        // First unregister if installed
        if HelperManager.shared.isHelperInstalled() {
            AppLogger.shared.log("ℹ️ [AutoFixer] Unregistering existing helper first")
            await HelperManager.shared.disconnect()
        }

        // Then install
        return await installPrivilegedHelper()
    }

    // MARK: - Driver Version Management

    private struct VHIDSnapshot {
        let serviceLoaded: Bool
        let serviceHealthy: Bool
        let daemonRunning: Bool
        let driverVersion: String?
    }

    private func captureVHIDSnapshot() async -> VHIDSnapshot {
        // Use extracted ServiceHealthChecker instead of LaunchDaemonInstaller
        let loaded = await ServiceHealthChecker.shared.isServiceLoaded(
            serviceID: "com.keypath.karabiner-vhiddaemon")
        let healthy = await ServiceHealthChecker.shared.isServiceHealthy(serviceID: "com.keypath.karabiner-vhiddaemon")
        let running = await vhidDeviceManager.detectRunning()
        let version = vhidDeviceManager.getInstalledVersion()
        return VHIDSnapshot(
            serviceLoaded: loaded,
            serviceHealthy: healthy,
            daemonRunning: running,
            driverVersion: version
        )
    }

    private func snapshotJSON(_ s: VHIDSnapshot) -> String {
        let ver = s.driverVersion ?? "null"
        return
            "{\"loaded\":\(s.serviceLoaded),\"healthy\":\(s.serviceHealthy),\"running\":\(s.daemonRunning),\"version\":\"\(ver)\"}"
    }

    private func logFixSessionSummary(
        session: String, action: String, success: Bool, start: Date, pre: VHIDSnapshot,
        post: VHIDSnapshot
    ) {
        let elapsed = String(format: "%.3f", Date().timeIntervalSince(start))
        let json =
            "{\"event\":\"VHIDFixSummary\",\"session\":\"\(session)\",\"action\":\"\(action)\",\"success\":\(success),\"elapsed_s\":\(elapsed),\"pre\":\(snapshotJSON(pre)),\"post\":\(snapshotJSON(post))}"
        AppLogger.shared.log(json)
    }

    private func installCorrectVHIDDriver() async -> Bool {
        AppLogger.shared.log(
            "🔧 [AutoFixer] Installing required Karabiner VirtualHID driver (helper-first)")

        let session = UUID().uuidString
        let t0 = Date()
        let pre = await captureVHIDSnapshot()

        do {
            try await PrivilegedOperationsCoordinator.shared.downloadAndInstallCorrectVHIDDriver()
        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Failed to auto-install driver via helper: \(error)")
            let post = await captureVHIDSnapshot()
            logFixSessionSummary(
                session: session, action: "installCorrectVHIDDriver", success: false, start: t0, pre: pre,
                post: post
            )
            return false
        }

        // Try to activate manager and verify daemon
        do {
            try await PrivilegedOperationsCoordinator.shared.activateVirtualHIDManager()
        } catch {
            AppLogger.shared.warn(
                "⚠️ [AutoFixer] activateVirtualHIDManager returned error (continuing): \(error)")
        }

        let restartOk = await restartVirtualHIDDaemon()
        AppLogger.shared.log("🔧 [AutoFixer] Post-install restart verified: \(restartOk)")
        let post = await captureVHIDSnapshot()
        logFixSessionSummary(
            session: session, action: "installCorrectVHIDDriver", success: restartOk, start: t0, pre: pre,
            post: post
        )
        return true
    }

    private func fixDriverVersionMismatch() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Fixing driver version mismatch")

        // Show dialog explaining the version downgrade
        guard let versionMessage = vhidDeviceManager.getVersionMismatchMessage() else {
            AppLogger.shared.warn("⚠️ [AutoFixer] No version mismatch message available")
            return false
        }

        AppLogger.shared.log("🔧 [AutoFixer] Got version message, showing dialog...")

        // Show user-facing dialog on main thread
        let userConfirmed = await MainActor.run {
            AppLogger.shared.log("🔧 [AutoFixer] Creating NSAlert on MainActor...")
            let alert = NSAlert()
            alert.messageText = "Karabiner Driver Version Fix Required"
            alert.informativeText = versionMessage
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Install v\(VHIDDeviceManager.requiredDriverVersionString)")
            alert.addButton(withTitle: "Cancel")

            AppLogger.shared.log("🔧 [AutoFixer] Calling runModal()...")
            let response = alert.runModal()
            AppLogger.shared.log("🔧 [AutoFixer] runModal() returned: \(response.rawValue)")
            return response == .alertFirstButtonReturn
        }

        AppLogger.shared.log("🔧 [AutoFixer] User confirmed: \(userConfirmed)")

        guard userConfirmed else {
            AppLogger.shared.log("ℹ️ [AutoFixer] User cancelled driver version fix")
            return false
        }

        // Install the correct version using coordinator (bundled pkg, no download)
        AppLogger.shared.log("🔧 [AutoFixer] Starting driver install via coordinator...")
        let session = UUID().uuidString
        let t0 = Date()
        let pre = await captureVHIDSnapshot()
        let success: Bool
        do {
            try await PrivilegedOperationsCoordinator.shared.downloadAndInstallCorrectVHIDDriver()
            AppLogger.shared.log("🔧 [AutoFixer] Coordinator call completed successfully")
            success = true
        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Coordinator failed to install driver: \(error)")
            success = false
        }

        if success {
            AppLogger.shared.info("✅ [AutoFixer] Successfully installed driver v\(VHIDDeviceManager.requiredDriverVersionString)")

            // Now start the Karabiner daemon services so the driver is actually usable
            AppLogger.shared.info("🔄 [AutoFixer] Starting Karabiner daemon services...")
            do {
                _ = try await PrivilegedOperationsCoordinator.shared.restartKarabinerDaemonVerified()
                AppLogger.shared.info("✅ [AutoFixer] Karabiner daemon started successfully")
            } catch {
                AppLogger.shared.error("⚠️ [AutoFixer] Failed to start Karabiner daemon: \(error)")
            }

            // Also ensure the VHID services are installed and running
            AppLogger.shared.info("🔄 [AutoFixer] Ensuring VHID services are running...")
            do {
                try await PrivilegedOperationsCoordinator.shared.restartUnhealthyServices()
                AppLogger.shared.info("✅ [AutoFixer] VHID services started successfully")
            } catch {
                AppLogger.shared.error("⚠️ [AutoFixer] Failed to restart VHID services: \(error)")
            }

            // Give services a moment to fully initialize
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Show success message
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Driver Version Fixed"
                alert.informativeText = """
                Karabiner-DriverKit-VirtualHIDDevice v\(VHIDDeviceManager.requiredDriverVersionString) has been installed and started successfully.

                ✓ Installed v\(VHIDDeviceManager.requiredDriverVersionString)
                ✓ Started Karabiner daemon services

                KeyPath is now ready to use.
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } else {
            AppLogger.shared.error("❌ [AutoFixer] Failed to fix driver version mismatch")

            // Show error message
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Installation Failed"
                alert.informativeText =
                    "Failed to install Karabiner-DriverKit-VirtualHIDDevice v\(VHIDDeviceManager.requiredDriverVersionString). Please try again or check the logs for details."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
        let post = await captureVHIDSnapshot()
        logFixSessionSummary(
            session: session, action: "fixDriverVersionMismatch", success: success, start: t0, pre: pre,
            post: post
        )
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
            AppLogger.shared.warn("⚠️ [AutoFixer] Failed to kill processes: \(error)")
        }

        // 2. Remove PID file
        try? PIDFileManager.removePID()
        AppLogger.shared.log("🗑️ [AutoFixer] Removed PID file")

        // 3. Oracle handles permission caching automatically
        AppLogger.shared.log("🔮 [AutoFixer] Oracle permission system - no manual cache clearing needed")

        // 4. Reset kanata manager state via the façade (installer fallback happens inside)
        AppLogger.shared.log("🔄 [AutoFixer] Restarting Kanata service via façade after nuclear reset")
        let restarted = await kanataManager.restartServiceWithFallback(
            reason: "WizardAutoFixer nuclear reset"
        )
        kanataManager.lastError = nil
        kanataManager.diagnostics.removeAll()
        if restarted {
            AppLogger.shared.info("🔄 [AutoFixer] Restarted Kanata service via façade")
        } else {
            AppLogger.shared.warn("⚠️ [AutoFixer] Kanata service restart failed post-reset")
        }

        // 5. Wait for system to settle
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        AppLogger.shared.info("✅ [AutoFixer] Reset complete - system should be in clean state")
        return true
    }

    // MARK: - Individual Auto-Fix Actions

    private func terminateConflictingProcesses() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Terminating conflicting kanata processes")

        // Use ProcessLifecycleManager to find external kanata processes
        let processManager = await MainActor.run { ProcessLifecycleManager() }
        let conflicts = await processManager.detectConflicts()

        if conflicts.externalProcesses.isEmpty {
            AppLogger.shared.info("✅ [AutoFixer] No external kanata processes to terminate")
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
            AppLogger.shared.info("✅ [AutoFixer] Conflicting kanata processes terminated")
            return true
        }

        AppLogger.shared.log(
            "⚠️ [AutoFixer] Still seeing \(remaining) external kanata process(es) after termination attempt"
        )
        return false
    }

    /// Try to kill a process by PID (helper-first; no AppleScript unless helper fails inside coordinator)
    private func killProcessByPID(_ pid: pid_t) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Terminating process via helper PID=\(pid)")
        do {
            try await PrivilegedOperationsCoordinator.shared.terminateProcess(pid)
        } catch {
            AppLogger.shared.error(
                "❌ [AutoFixer] Helper terminateProcess failed for PID=\(pid): \(error.localizedDescription)"
            )
            return false
        }

        // Verify exit
        try? await Task.sleep(nanoseconds: 400_000_000)
        let still = runCommand("/bin/kill", ["-0", String(pid)]) == 0
        if still {
            AppLogger.shared.warn("⚠️ [AutoFixer] PID=\(pid) still appears alive after helper termination")
            return false
        } else {
            AppLogger.shared.info("✅ [AutoFixer] PID=\(pid) no longer running after helper termination")
            return true
        }
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

        // CRITICAL: Ensure manager is activated BEFORE starting daemon
        // Per Karabiner documentation, manager activation must happen before daemon startup
        if !vhidDeviceManager.detectActivation() {
            AppLogger.shared.log(
                "⚠️ [AutoFixer] VirtualHID Manager not activated - activating now before starting daemon")
            let activationSuccess = await activateVHIDDeviceManager()
            if !activationSuccess {
                AppLogger.shared.error(
                    "❌ [AutoFixer] Manager activation failed - cannot start daemon without it")
                return false
            }
            AppLogger.shared.log("✅ [AutoFixer] Manager activated successfully, proceeding to start daemon")
        } else {
            AppLogger.shared.log("ℹ️ [AutoFixer] Manager already activated, proceeding to start daemon")
        }

        let success = await kanataManager.startKarabinerDaemon()

        if success {
            AppLogger.shared.info("✅ [AutoFixer] Successfully started Karabiner daemon")
        } else {
            AppLogger.shared.error("❌ [AutoFixer] Failed to start Karabiner daemon")
        }

        return success
    }

    /// Restart VirtualHID daemon with verification
    /// ⚠️ RELIABILITY ROLLBACK (Nov 2025): If this becomes flaky, restore the legacy fallback:
    /// - Uncomment the legacyRestartVirtualHIDDaemon() call below
    /// - Also increase timing constants in PrivilegedOperationsCoordinator
    private func restartVirtualHIDDaemon() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Fixing VirtualHID connection health issues")

        // Step 1: Try to clear Kanata log to reset connection health detection
        await clearKanataLog()

        // Step 2: Use proper restart that kills all duplicates first (optimized Nov 2025)
        AppLogger.shared.log("🔧 [AutoFixer] Restarting VirtualHID daemon (kill duplicates + verify)")
        let restartSuccess = await kanataManager.restartKarabinerDaemon()

        if restartSuccess {
            // Refresh process state after successful restart to update isRunning
            let manager = kanataManager
            await MainActor.run {
                manager.refreshProcessState()
            }
            AppLogger.shared.info(
                "✅ [AutoFixer] Successfully restarted VirtualHID daemon (verified healthy)")
            return true
        } else {
            AppLogger.shared.error(
                "❌ [AutoFixer] VirtualHID daemon restart failed - user can retry via Fix button")
            // Removed legacy fallback cascade (Nov 2025 optimization) - user can click Fix again
            // To restore: uncomment below and increase timing constants in PrivilegedOperationsCoordinator
            // AppLogger.shared.warn("⚠️ [AutoFixer] Trying legacy restart as fallback")
            // return await legacyRestartVirtualHIDDaemon()
            return false
        }
    }

    private func repairVHIDDaemonServices() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Repairing VHID LaunchDaemon services")
        do {
            try await PrivilegedOperationsCoordinator.shared.repairVHIDDaemonServices()
            AppLogger.shared.info("✅ [AutoFixer] Repaired VHID LaunchDaemon services")
            return true
        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Failed to repair VHID LaunchDaemon services: \(error)")
            return false
        }
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
                AppLogger.shared.info("✅ [AutoFixer] Successfully cleared Kanata log")
            } else {
                AppLogger.shared.log(
                    "⚠️ [AutoFixer] Could not clear Kanata log (may require admin privileges)")
            }
        } catch {
            AppLogger.shared.warn("⚠️ [AutoFixer] Error clearing Kanata log: \(error)")
        }
    }

    /// Force activate VirtualHID Manager using the manager application
    private func forceActivateVirtualHIDManager() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Force activating VirtualHID Manager")

        let managerPath =
            "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

        guard FileManager.default.fileExists(atPath: managerPath) else {
            AppLogger.shared.error("❌ [AutoFixer] VirtualHID Manager not found at expected path")
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
                            AppLogger.shared.info("✅ [AutoFixer] VirtualHID Manager force activation completed")
                        } else {
                            AppLogger.shared.log(
                                "❌ [AutoFixer] VirtualHID Manager force activation failed with status: \(process.terminationStatus)"
                            )
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
                        AppLogger.shared.error("❌ [AutoFixer] Error starting VirtualHID Manager: \(error)")
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
                AppLogger.shared.info("✅ [AutoFixer] Legacy VirtualHID daemon restart completed")
            } else {
                AppLogger.shared.error("❌ [AutoFixer] Legacy VirtualHID daemon restart failed")
            }

            return startSuccess

        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Error in legacy VirtualHID daemon restart: \(error)")
            return false
        }
    }

    private func installMissingComponents() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Installing missing components")

        let success = await kanataManager.performTransparentInstallation()

        if success {
            AppLogger.shared.info("✅ [AutoFixer] Successfully installed missing components")
        } else {
            AppLogger.shared.error("❌ [AutoFixer] Failed to install missing components")
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

            AppLogger.shared.info("✅ [AutoFixer] Successfully created config directories")
            return true

        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Failed to create config directories: \(error)")
            return false
        }
    }

    private func activateVHIDDeviceManager() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Activating VHIDDevice Manager")

        // First try automatic activation using coordinator
        let success: Bool
        do {
            try await PrivilegedOperationsCoordinator.shared.activateVirtualHIDManager()
            success = true
        } catch {
            AppLogger.shared.warn("⚠️ [AutoFixer] Coordinator activation failed: \(error)")
            success = false
        }

        if success {
            AppLogger.shared.info("✅ [AutoFixer] Successfully activated VHIDDevice Manager")
            return true
        } else {
            AppLogger.shared.log(
                "⚠️ [AutoFixer] Automatic activation failed - showing user dialog for manual activation")

            // Show dialog to guide user through manual driver extension activation
            if TestEnvironment.isRunningTests {
                AppLogger.shared.debug(
                    "🧪 [AutoFixer] Suppressing driver extension dialog in test environment")
            } else {
                await showDriverExtensionDialog()
            }

            // Wait a moment for user to potentially complete the action
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            // Check if activation succeeded after user intervention
            let manualSuccess = vhidDeviceManager.detectActivation()

            if manualSuccess {
                AppLogger.shared.info("✅ [AutoFixer] VHIDDevice Manager activated after user intervention")
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
                let url = URL(string: "x-apple.systempreferences:com.apple.SystemExtensionsSettings")!
                NSWorkspace.shared.open(url)
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
        AppLogger.shared.log(
            "🔧 [AutoFixer] *** ENTRY POINT *** installLaunchDaemonServices() called")

        // CRITICAL: Ensure manager is activated BEFORE installing daemon services
        // Per Karabiner documentation, manager activation must happen before daemon startup
        if !vhidDeviceManager.detectActivation() {
            AppLogger.shared.log(
                "⚠️ [AutoFixer] VirtualHID Manager not activated - activating now before daemon install")
            let activationSuccess = await activateVHIDDeviceManager()
            if !activationSuccess {
                AppLogger.shared.error(
                    "❌ [AutoFixer] Manager activation failed - cannot install daemon services without it")
                return false
            }
            AppLogger.shared.log("✅ [AutoFixer] Manager activated successfully, proceeding with daemon install")
        } else {
            AppLogger.shared.log("ℹ️ [AutoFixer] Manager already activated, proceeding with daemon install")
        }

        AppLogger.shared.log(
            "🔧 [AutoFixer] Installing LaunchDaemon services using InstallerEngine façade")

        // Use RuntimeCoordinator.runFullInstall() which delegates to InstallerEngine
        // Handles everything through the façade:
        // - Inspects system state
        // - Creates an installation plan
        // - Executes recipes (install plists, create config, load services)
        let report = await kanataManager.runFullInstall(reason: "WizardAutoFixer install LaunchDaemons")
        if report.success {
            AppLogger.shared.log(
                "✅ [AutoFixer] LaunchDaemon installation completed successfully via InstallerEngine")

            let restarted = await kanataManager.restartServiceWithFallback(
                reason: "WizardAutoFixer launch daemon install"
            )
            if restarted {
                AppLogger.shared.info("🔄 [AutoFixer] Kanata service restarted after LaunchDaemon install")
            } else {
                AppLogger.shared.warn(
                    "⚠️ [AutoFixer] Kanata service restart failed after LaunchDaemon install (may require approval)")
            }
            return true
        } else {
            let reason = report.failureReason ?? "Unknown error"
            AppLogger.shared.error("❌ [AutoFixer] LaunchDaemon installation failed: \(reason)")
            return false
        }
    }

    private func installBundledKanata() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Installing bundled kanata binary to system location")

        let totalSteps = 2
        var stepsCompleted = 0

        // Step 1: Check if bundled binary is available and properly signed
        AppLogger.shared.log("🔧 [AutoFixer] Step 1/\(totalSteps): Verifying bundled kanata binary...")
        let bundledManager = await BundledRuntimeCoordinator()
        let signingStatus = await bundledManager.bundledKanataSigningStatus()

        guard signingStatus.isDeveloperID else {
            AppLogger.shared.error(
                "❌ [AutoFixer] Step 1 FAILED: Bundled kanata binary is not properly signed: \(signingStatus)"
            )
            return false
        }
        AppLogger.shared.info("✅ [AutoFixer] Step 1 SUCCESS: Bundled kanata binary is properly signed")
        stepsCompleted += 1

        // Step 2: Install bundled binary to system location
        AppLogger.shared.log(
            "🔧 [AutoFixer] Step 2/\(totalSteps): Installing bundled binary to system location...")
        let installSuccess = await bundledManager.replaceBinaryWithBundled()

        if installSuccess {
            stepsCompleted += 1
            AppLogger.shared.info(
                "✅ [AutoFixer] Step 2 SUCCESS: Bundled kanata binary installed successfully")

        } else {
            AppLogger.shared.error("❌ [AutoFixer] Step 2 FAILED: Failed to install bundled kanata binary")
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
                    AppLogger.shared.info("✅ [AutoFixer] Process \(pid) terminated gracefully")
                    return true
                } else {
                    // Process still running, try SIGKILL
                    AppLogger.shared.warn("⚠️ [AutoFixer] Process \(pid) still running, using SIGKILL")
                    return await forceTerminateProcess(pid: pid)
                }
            } else {
                AppLogger.shared.error("❌ [AutoFixer] Failed to send SIGTERM to process \(pid)")
                return await forceTerminateProcess(pid: pid)
            }
        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Error terminating process \(pid): \(error)")
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
                AppLogger.shared.info("✅ [AutoFixer] Force terminated process \(pid)")
            } else {
                AppLogger.shared.error("❌ [AutoFixer] Failed to force terminate process \(pid)")
            }
            return success

        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Error force terminating process \(pid): \(error)")
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
                AppLogger.shared.error(
                    "❌ [AutoFixer] Source config file does not exist at \(userConfigPath)")
                return false
            }

            // Read the user config
            let configContent = try String(contentsOfFile: userConfigPath, encoding: .utf8)
            AppLogger.shared.log("📄 [AutoFixer] Read \(configContent.count) characters from user config")

            // Use AppleScript to write to system location with admin privileges
            let script = """
            do shell script "echo '\(configContent.replacingOccurrences(of: "'", with: "\\'"))' > '\(systemConfigPath)'" with administrator privileges
            """

            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            _ = appleScript?.executeAndReturnError(&error)

            if let error {
                AppLogger.shared.error("❌ [AutoFixer] AppleScript error: \(error)")
                return false
            }

            // Verify the file was written
            if FileManager.default.fileExists(atPath: systemConfigPath) {
                let systemContent = try String(contentsOfFile: systemConfigPath, encoding: .utf8)
                let success = systemContent == configContent

                if success {
                    AppLogger.shared.info("✅ [AutoFixer] Config successfully synchronized to system location")
                    AppLogger.shared.info(
                        "🔄 [AutoFixer] Config synchronized - changes will be applied via TCP reload commands")
                } else {
                    AppLogger.shared.error("❌ [AutoFixer] Config content mismatch after copy")
                }

                return success
            } else {
                AppLogger.shared.error("❌ [AutoFixer] System config file was not created")
                return false
            }

        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Error synchronizing config paths: \(error)")
            return false
        }
    }

    private func restartUnhealthyServices() async -> Bool {
        // IMMEDIATE crash-proof logging
        Swift.print("*** IMMEDIATE DEBUG *** restartUnhealthyServices() called at \(Date())")
        try? "*** IMMEDIATE DEBUG *** restartUnhealthyServices() called at \(Date())\n".write(
            to: URL(fileURLWithPath: NSHomeDirectory() + "/restart-services-debug.txt"), atomically: true,
            encoding: .utf8
        )

        AppLogger.shared.log(
            "🔧 [AutoFixer] *** ENHANCED DEBUGGING *** restartUnhealthyServices() called")
        AppLogger.shared.log("🔧 [AutoFixer] Timestamp: \(Date())")
        AppLogger.shared.log("🔧 [AutoFixer] OnMainActor: true")
        AppLogger.shared.log(
            "🔧 [AutoFixer] This means the new logic is working - will install missing + restart unhealthy"
        )

        // Fast path: attempt restart via KanataService façade before doing privileged repairs.
        AppLogger.shared.log(
            "🔄 [AutoFixer] Fast path: attempting KanataService restart before privileged repairs")
        let fastRestart = await kanataManager.restartServiceWithFallback(
            reason: "WizardAutoFixer restart unhealthy (fast path)"
        )
        if fastRestart {
            AppLogger.shared.info(
                "✅ [AutoFixer] Fast path restart succeeded via KanataService - skipping privileged repairs")
            return true
        }
        AppLogger.shared.warn(
            "⚠️ [AutoFixer] Fast path restart failed - continuing with privileged repair workflow")

        // Get current status to determine what needs to be done
        AppLogger.shared.log("🔧 [AutoFixer] Step 1: Getting current service status...")
        let status = await InstallerEngine().getServiceStatus()

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
        // IMPORTANT: Don't install Kanata if SMAppService is managing it (even if launchctl print fails)
        let needsInstallation = !status.allServicesLoaded

        // Check if legacy exists - if so, auto-resolve by removing it
        let hasLegacy = await MainActor.run {
            KanataDaemonManager.shared.hasLegacyInstallation()
        }
        let isRegistered = await MainActor.run {
            KanataDaemonManager.isRegisteredViaSMAppService()
        }

        // CRITICAL FIX: Check if Kanata is actually managed by SMAppService before installing
        let smAppServiceStatus = await MainActor.run {
            KanataDaemonManager.shared.getStatus()
        }
        let isSMAppServiceActive = await MainActor.run {
            KanataDaemonManager.isUsingSMAppService
        }
        // Also check if process is running (SMAppService might have status .notFound but process is running)
        let healthStatus = await InstallerEngine().checkKanataServiceHealth()
        let isProcessRunning = healthStatus.isRunning

        // If SMAppService is managing Kanata (enabled OR requiresApproval) OR process is running, don't trigger installation
        let shouldSkipInstallation =
            (isSMAppServiceActive || smAppServiceStatus == .requiresApproval || isProcessRunning)
                && needsInstallation

        AppLogger.shared.log("🔍 [AutoFixer] Installation check: needsInstallation=\(needsInstallation)")
        AppLogger.shared.log(
            "🔍 [AutoFixer] SMAppService status: \(smAppServiceStatus.rawValue) (\(String(describing: smAppServiceStatus)))"
        )
        AppLogger.shared.log(
            "🔍 [AutoFixer] SMAppService active: \(isSMAppServiceActive), Process running: \(isProcessRunning)"
        )
        AppLogger.shared.log("🔍 [AutoFixer] Should skip installation: \(shouldSkipInstallation)")
        AppLogger.shared.log("🔍 [AutoFixer] Legacy installation: \(hasLegacy)")
        AppLogger.shared.log("🔍 [AutoFixer] SMAppService registered: \(isRegistered)")

        // If legacy exists, auto-resolve by removing it
        if hasLegacy, !isRegistered {
            AppLogger.shared.log(
                "🔄 [AutoFixer] Legacy plist detected - auto-resolving by removing legacy")
            // This will be handled by createConfigureAndLoadAllServices() which auto-resolves conflicts
        }

        // Check for registered-but-not-loaded state (common after clean uninstall)
        let isRegisteredButNotLoaded = await KanataDaemonManager.shared.isRegisteredButNotLoaded()

        if isRegisteredButNotLoaded {
            AppLogger.shared.log(
                "🔄 [AutoFixer] Step 1.5: Detected registered-but-not-loaded state")
            AppLogger.shared.log(
                "🔧 [AutoFixer] Fixing by unregistering and re-registering service to force launchd to load"
            )

            do {
                // First unregister to clear stale SMAppService metadata
                AppLogger.shared.log("🗑️ [AutoFixer] Unregistering stale service...")
                try await KanataDaemonManager.shared.unregister()

                // Wait briefly for unregistration to complete
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms

                // Re-register to force launchd to load
                AppLogger.shared.log("📝 [AutoFixer] Re-registering service...")
                try await KanataDaemonManager.shared.register()

                // Wait for launchd to load the service
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                AppLogger.shared.info(
                    "✅ [AutoFixer] Successfully fixed registered-but-not-loaded state")
            } catch {
                AppLogger.shared.error(
                    "❌ [AutoFixer] Failed to fix registered-but-not-loaded state: \(error)")
                // Continue anyway - restart logic below might still help
            }
        }

        if needsInstallation, !shouldSkipInstallation {
            AppLogger.shared.log(
                "🔧 [AutoFixer] Step 2: Some services not loaded, installing via InstallerEngine façade")
            let report = await kanataManager.runFullInstall(reason: "WizardAutoFixer install missing services")
            if report.success {
                AppLogger.shared.info("✅ [AutoFixer] Installed/migrated services via InstallerEngine")
            } else {
                let reason = report.failureReason ?? "Unknown error"
                AppLogger.shared.error("❌ [AutoFixer] Failed to install/migrate services: \(reason)")
                return false
            }
        } else {
            AppLogger.shared.log(
                "🔧 [AutoFixer] Step 2: All services already loaded and using correct method, skipping installation"
            )
        }

        // Step 2: Restart any unhealthy services
        AppLogger.shared.log(
            "🔧 [AutoFixer] Step 3: Calling comprehensive restart method via coordinator")
        AppLogger.shared.log(
            "🔧 [AutoFixer] About to call: coordinator.restartUnhealthyServices()")

        let restartSuccess: Bool
        do {
            try await PrivilegedOperationsCoordinator.shared.restartUnhealthyServices()
            restartSuccess = true
        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Coordinator restart failed: \(error)")
            restartSuccess = false
        }

        AppLogger.shared.log(
            "🔧 [AutoFixer] Step 4: ServiceBootstrapper.restartUnhealthyServices() returned: \(restartSuccess)"
        )
        AppLogger.shared.log("🔧 [AutoFixer] Checking final service status after restart...")

        let finalStatus = await InstallerEngine().getServiceStatus()
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
            AppLogger.shared.info("✅ [AutoFixer] Successfully fixed unhealthy LaunchDaemon services")
        } else {
            AppLogger.shared.error("❌ [AutoFixer] Failed to fix unhealthy services - analyzing cause...")
            AppLogger.shared.error("❌ [AutoFixer] This usually means:")
            AppLogger.shared.error("❌ [AutoFixer] 1. Admin password was not provided when prompted")
            AppLogger.shared.error("❌ [AutoFixer] 2. Missing services installation failed")
            AppLogger.shared.error("❌ [AutoFixer] 3. launchctl restart commands were denied by system")
            AppLogger.shared.log(
                "❌ [AutoFixer] 4. Services restarted but are still unhealthy (permission/config issues)")
            AppLogger.shared.log(
                "💡 [AutoFixer] SOLUTION: Try the Fix button again and provide admin password when prompted")
        }

        AppLogger.shared.log(
            "🔧 [AutoFixer] *** restartUnhealthyServices() COMPLETE *** Returning: \(restartSuccess)")
        Swift.print("*** IMMEDIATE DEBUG *** restartUnhealthyServices() returning: \(restartSuccess)")
        try? "*** IMMEDIATE DEBUG *** restartUnhealthyServices() returning: \(restartSuccess)\n".write(
            to: URL(fileURLWithPath: NSHomeDirectory() + "/restart-services-debug.txt"),
            atomically: false, encoding: .utf8
        )
        return restartSuccess
    }

    // MARK: - Orphaned Process Auto-Fix Actions

    /// Adopt an existing orphaned Kanata process by installing LaunchDaemon management
    private func adoptOrphanedProcess() async -> Bool {
        AppLogger.shared.log("🔗 [AutoFixer] Starting orphaned process adoption")

        // Install LaunchDaemon service files without loading/starting them (no interference with running process)
        AppLogger.shared.log(
            "🔗 [AutoFixer] Installing LaunchDaemon service files for future management")
        do {
            try await PrivilegedOperationsCoordinator.shared.installLaunchDaemonServicesWithoutLoading()
            AppLogger.shared.info("✅ [AutoFixer] Successfully adopted orphaned Kanata process")
            return true
        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Failed to adopt orphaned process: \(error)")
            return false
        }
    }

    /// Replace an orphaned Kanata process with a properly managed one
    private func replaceOrphanedProcess() async -> Bool {
        AppLogger.shared.info("🔄 [AutoFixer] Starting orphaned process replacement")

        // Step 1: Kill existing process
        AppLogger.shared.info("🔄 [AutoFixer] Step 1: Terminating orphaned Kanata process")

        let terminateSuccess = await terminateConflictingProcesses()

        if !terminateSuccess {
            AppLogger.shared.warn("⚠️ [AutoFixer] Warning: Failed to cleanly terminate orphaned process")
        }

        // Step 2: Install and start managed service
        AppLogger.shared.info("🔄 [AutoFixer] Step 2: Installing and starting managed Kanata service")

        let installSuccess = await installLaunchDaemonServices()

        if installSuccess {
            AppLogger.shared.info(
                "✅ [AutoFixer] Successfully replaced orphaned process with managed service")
            return true
        } else {
            AppLogger.shared.error("❌ [AutoFixer] Failed to start managed service")
            return false
        }
    }

    // MARK: - Log Rotation Auto-Fix

    /// Install log rotation service to keep Kanata logs under 10MB total
    private func installLogRotation() async -> Bool {
        AppLogger.shared.log("📝 [AutoFixer] Installing log rotation service for Kanata logs")

        do {
            try await PrivilegedOperationsCoordinator.shared.installLogRotation()
            AppLogger.shared.info("✅ [AutoFixer] Successfully installed log rotation service")
            return true
        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Failed to install log rotation service: \(error)")
            return false
        }
    }

    private func replaceKanataWithBundled() async -> Bool {
        AppLogger.shared.log(
            "🔧 [AutoFixer] Replacing system kanata with bundled Developer ID signed version")

        let success = await bundledRuntimeCoordinator.replaceBinaryWithBundled()

        if success {
            AppLogger.shared.info(
                "✅ [AutoFixer] Successfully replaced system kanata with bundled version")

            // Restart the kanata service to use the new binary via façade + fallback path
            AppLogger.shared.info("🔄 [AutoFixer] Restarting kanata service to use new binary")
            let restarted = await kanataManager.restartServiceWithFallback(
                reason: "AutoFixer replace bundled kanata binary"
            )
            if restarted {
                AppLogger.shared.info("✅ [AutoFixer] Restarted kanata service with new binary")
            } else {
                AppLogger.shared.warn("⚠️ [AutoFixer] Service restart failed after binary replace")
            }

            return true
        } else {
            AppLogger.shared.error("❌ [AutoFixer] Failed to replace kanata binary")
            return false
        }
    }

    // MARK: - TCP Communication Server Auto-Fix Actions

    private func enableTCPServer() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Enabling TCP server")

        // TCP is enabled by default through port configuration
        // Just regenerate service configuration with current settings
        return await regenerateCommServiceConfiguration()
    }

    private func setupTCPAuthentication() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Setting up TCP communication (authentication removed in Kanata v1.9.0)")

        // Regenerate service configuration
        let regenSuccess = await regenerateCommServiceConfiguration()
        guard regenSuccess else {
            AppLogger.shared.error("❌ [AutoFixer] Failed to regenerate service configuration")
            return false
        }

        // Restart server to adopt new configuration
        let restartSuccess = await restartCommServer()
        guard restartSuccess else {
            AppLogger.shared.error("❌ [AutoFixer] Failed to restart communication server")
            return false
        }

        // Test server connectivity
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port, timeout: 5.0)

        let isHealthy = await client.checkServerStatus()

        // FIX #1: Explicitly close connection to prevent file descriptor leak
        await client.cancelInflightAndCloseConnection()

        if isHealthy {
            AppLogger.shared.info("✅ [AutoFixer] TCP communication setup successful")
            return true
        } else {
            AppLogger.shared.error("❌ [AutoFixer] TCP server connectivity test failed")
            return false
        }
    }

    private func regenerateCommServiceConfiguration() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Regenerating communication service configuration")

        do {
            try await PrivilegedOperationsCoordinator.shared.regenerateServiceConfiguration()
            AppLogger.shared.info(
                "✅ [AutoFixer] Successfully regenerated communication service configuration")
            return true
        } catch {
            AppLogger.shared.error(
                "❌ [AutoFixer] Failed to regenerate communication service configuration: \(error)")
            return false
        }
    }

    private func restartCommServer() async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Restarting communication server")

        do {
            try await PrivilegedOperationsCoordinator.shared.restartUnhealthyServices()
            AppLogger.shared.info("✅ [AutoFixer] Successfully restarted communication server")
            return true
        } catch {
            AppLogger.shared.error("❌ [AutoFixer] Failed to restart communication server: \(error)")
            return false
        }
    }
}
