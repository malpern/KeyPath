import ApplicationServices
import Foundation
import IOKit.hidsystem
import Network
import SwiftUI

// MARK: - KanataManager Lifecycle Extension

extension KanataManager {
    // MARK: - Process Synchronization and Initialization

    func performInitialization() async {
        // Prevent concurrent initialization
        if isInitializing {
            AppLogger.shared.log("⚠️ [Init] Already initializing - skipping duplicate initialization")
            return
        }

        isInitializing = true
        defer { isInitializing = false }

        await updateStatus()

        // First, adopt any existing KeyPath-looking kanata processes before deciding to auto-start
        var lifecycle: ProcessLifecycleManager!
        await MainActor.run {
            lifecycle = ProcessLifecycleManager(kanataManager: self)
        }
        await lifecycle.recoverFromCrash()
        await updateStatus()
        // Try to start Kanata automatically on launch if all requirements are met
        let status = await getSystemRequirementsStatus()

        // Check if Kanata is already running before attempting to start
        if isRunning {
            AppLogger.shared.log("✅ [Init] Kanata is already running - skipping initialization")
            return
        }

        // Auto-start kanata if all requirements are met
        AppLogger.shared.log(
            "🔍 [Init] Status: installed=\(status.installed), permissions=\(status.permissions), driver=\(status.driver), daemon=\(status.daemon)"
        )

        if status.installed, status.permissions, status.driver, status.daemon {
            AppLogger.shared.log("✅ [Init] All requirements met - auto-starting Kanata")
            await startKanata()
        } else {
            AppLogger.shared.log("⚠️ [Init] Requirements not met - skipping auto-start")
            if !status.installed { AppLogger.shared.log("  - Missing: Kanata binary") }
            if !status.permissions { AppLogger.shared.log("  - Missing: Required permissions") }
            if !status.driver { AppLogger.shared.log("  - Missing: VirtualHID driver") }
            if !status.daemon { AppLogger.shared.log("  - Missing: VirtualHID daemon") }
        }

        // Start config file watching regardless of whether Kanata started
        // This allows hot reload to work even if Kanata starts later
        await MainActor.run {
            startConfigFileWatching()
        }
    }

    // MARK: - Recovery Operations

    func attemptKeyboardRecovery() async {
        AppLogger.shared.log("🔧 [Recovery] Starting keyboard recovery process...")

        // Step 1: Ensure all Kanata processes are killed
        AppLogger.shared.log("🔧 [Recovery] Step 1: Killing any remaining Kanata processes")
        await killAllKanataProcesses()

        // Step 2: Wait for system to release keyboard control
        AppLogger.shared.log("🔧 [Recovery] Step 2: Waiting 2 seconds for keyboard release...")
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Step 3: Restart VirtualHID daemon
        AppLogger.shared.log("🔧 [Recovery] Step 3: Attempting to restart Karabiner daemon...")
        await restartKarabinerDaemon()

        // Step 4: Wait before retry
        AppLogger.shared.log("🔧 [Recovery] Step 4: Waiting 3 seconds before retry...")
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Step 5: Try starting Kanata again with validation
        AppLogger.shared.log(
            "🔧 [Recovery] Step 5: Attempting to restart Kanata with VirtualHID validation...")
        await startKanataWithValidation()

        AppLogger.shared.log("🔧 [Recovery] Keyboard recovery process complete")
    }

    func killAllKanataProcesses() async {
        let script = """
        do shell script "/usr/bin/pkill -f kanata" with administrator privileges with prompt "KeyPath needs to stop keyboard remapping processes."
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.log("🔧 [Recovery] Killed Kanata processes")
            } else {
                AppLogger.shared.log(
                    "⚠️ [Recovery] Failed to kill Kanata processes - exit code: \(task.terminationStatus)")
            }
        } catch {
            AppLogger.shared.log("⚠️ [Recovery] Failed to kill Kanata processes: \(error)")
        }
    }

    func restartKarabinerDaemon() async {
        // First kill the daemon
        let killScript =
            "do shell script \"/usr/bin/pkill -f Karabiner-VirtualHIDDevice-Daemon\" with administrator privileges with prompt \"KeyPath needs to restart the virtual keyboard daemon.\""

        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        killTask.arguments = ["-e", killScript]

        do {
            try killTask.run()
            killTask.waitUntilExit()

            if killTask.terminationStatus == 0 {
                AppLogger.shared.log("🔧 [Recovery] Killed Karabiner daemon")
            } else {
                AppLogger.shared.log(
                    "⚠️ [Recovery] Failed to kill Karabiner daemon - exit code: \(killTask.terminationStatus)")
            }

            // Wait a moment then check if it auto-restarts
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Check VirtualHID daemon status
            let vhidDeviceManager = VHIDDeviceManager()
            let status = vhidDeviceManager.getDetailedStatus()
            AppLogger.shared.log("🔧 [Recovery] VirtualHID daemon restart - running: \(status.daemonRunning)")

        } catch {
            AppLogger.shared.log("⚠️ [Recovery] Failed to restart Karabiner daemon: \(error)")
        }
    }
}
