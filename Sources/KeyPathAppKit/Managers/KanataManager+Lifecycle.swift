import ApplicationServices
import Foundation
import IOKit.hidsystem
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import Network
import SwiftUI

// MARK: - KanataManager Lifecycle Extension

extension KanataManager {
    // MARK: - Process Synchronization and Initialization

    func performInitialization() async {
        // Prevent concurrent initialization
        if isInitializing {
            AppLogger.shared.warn("⚠️ [Init] Already initializing - skipping duplicate initialization")
            return
        }

        isInitializing = true
        defer { isInitializing = false }

        // Use InstallerEngine to orchestrate initialization
        let engine = InstallerEngine()

        // Create default config if missing
        let ensuredConfig = await createDefaultUserConfigIfMissing()
        if ensuredConfig {
            AppLogger.shared.log("✅ [Init] Verified user config exists at \(configPath)")
        }

        // Initial status check
        await updateStatus()

        // Try to start Kanata automatically on launch if environment allows
        let context = await engine.inspectSystem()

        // Check if Kanata is already running
        if context.services.kanataRunning {
            AppLogger.shared.info("✅ [Init] Kanata is already running - skipping initialization")
            return
        }

        // In headless/production mode, we might want to auto-repair/start
        // For now, we'll just log the state and let the UI drive the installation flow
        // unless we are in a state where we *expect* it to be running.

        AppLogger.shared.log(
            "🔍 [Init] System Context: installed=\(context.components.kanataBinaryInstalled), permissions=\(context.permissions.isSystemReady)"
        )

        // Start config file watching
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
            AppLogger.shared.info("✅ [Recovery] Karabiner daemon restart verified")
        } else {
            AppLogger.shared.warn("⚠️ [Recovery] Karabiner daemon restart failed or not verified")
        }

        // Step 4: Wait before retry
        AppLogger.shared.log("🔧 [Recovery] Step 4: Waiting 3 seconds before retry...")
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Step 5: Try starting Kanata again via InstallerEngine
        AppLogger.shared.log(
            "🔧 [Recovery] Step 5: Attempting to restart Kanata with VirtualHID validation...")
        _ = await InstallerEngine().run(intent: .repair, using: PrivilegeBroker())

        AppLogger.shared.log("🔧 [Recovery] Keyboard recovery process complete")
    }

    func killAllKanataProcesses() async {
        do {
            try await PrivilegedOperationsCoordinator.shared.killAllKanataProcesses()
            AppLogger.shared.log("🔧 [Recovery] Killed Kanata processes")
        } catch {
            AppLogger.shared.warn("⚠️ [Recovery] Failed to kill Kanata processes: \(error)")
        }
    }
}
