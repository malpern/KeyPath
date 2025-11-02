import ApplicationServices
import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathDaemonLifecycle
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
        let lifecycle = ProcessLifecycleManager()
        await lifecycle.cleanupOrphanedProcesses()
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

        // Step 3: Restart VirtualHID daemon (uses new verified restart)
        AppLogger.shared.log("🔧 [Recovery] Step 3: Attempting to restart Karabiner daemon...")
        let restartSuccess = await restartKarabinerDaemon()
        if restartSuccess {
            AppLogger.shared.log("✅ [Recovery] Karabiner daemon restart verified")
        } else {
            AppLogger.shared.log("⚠️ [Recovery] Karabiner daemon restart failed or not verified")
        }

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
        do {
            try await PrivilegedOperationsCoordinator.shared.killAllKanataProcesses()
            AppLogger.shared.log("🔧 [Recovery] Killed Kanata processes")
        } catch {
            AppLogger.shared.log("⚠️ [Recovery] Failed to kill Kanata processes: \(error)")
        }
    }

    /// Legacy coordinator-based restart - now delegates to verified restart for safety
    func restartKarabinerDaemonLegacy() async {
        do {
            let ok = try await PrivilegedOperationsCoordinator.shared.restartKarabinerDaemonVerified()
            AppLogger.shared.log("🔧 [Recovery] Restarted Karabiner daemon (legacy path via verified): \(ok)")

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
