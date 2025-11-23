import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle

/// Protocol for coordinating process lifecycle operations
/// Provides a unified interface for starting, stopping, and restarting Kanata service
@MainActor
protocol ProcessCoordinating: AnyObject {
    /// Start the Kanata service
    /// - Returns: True if service started successfully
    func startService() async -> Bool

    /// Stop the Kanata service
    /// - Returns: True if service stopped successfully
    func stopService() async -> Bool

    /// Restart the Kanata service
    /// - Returns: True if service restarted successfully
    func restartService() async -> Bool

    /// Check if the service is currently running
    /// - Returns: True if service is running
    func isServiceRunning() async -> Bool
}

/// Coordinates process lifecycle operations by delegating to InstallerEngine
/// This provides a clean interface for RuntimeCoordinator (formerly RuntimeCoordinator)
@MainActor
final class ProcessCoordinator: ProcessCoordinating {
    private let installerEngine: InstallerEngine
    private let privilegeBroker: PrivilegeBroker

    init(
        installerEngine: InstallerEngine? = nil,
        privilegeBroker: PrivilegeBroker? = nil
    ) {
        self.installerEngine = installerEngine ?? InstallerEngine()
        self.privilegeBroker = privilegeBroker ?? PrivilegeBroker()
    }

    func startService() async -> Bool {
        AppLogger.shared.log("🚀 [ProcessCoordinator] Starting Kanata service...")

        // Use InstallerEngine to start the service
        let report = await installerEngine.run(intent: .repair, using: privilegeBroker)

        if report.success {
            AppLogger.shared.log("✅ [ProcessCoordinator] Service started successfully")
            return true
        } else {
            AppLogger.shared.warn("⚠️ [ProcessCoordinator] Service start failed: \(report.failureReason ?? "Unknown error")")
            return false
        }
    }

    func stopService() async -> Bool {
        AppLogger.shared.log("🛑 [ProcessCoordinator] Stopping Kanata service...")

        // Use PrivilegeBroker to stop the service directly
        do {
            try await privilegeBroker.stopKanataService()
            AppLogger.shared.log("✅ [ProcessCoordinator] Service stopped successfully")
            return true
        } catch {
            AppLogger.shared.warn("⚠️ [ProcessCoordinator] Service stop failed: \(error)")
            return false
        }
    }

    func restartService() async -> Bool {
        AppLogger.shared.log("🔄 [ProcessCoordinator] Restarting Kanata service...")

        // Stop first
        let stopped = await stopService()
        guard stopped else {
            AppLogger.shared.warn("⚠️ [ProcessCoordinator] Failed to stop service before restart")
            return false
        }

        // Wait a moment for cleanup
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Start again
        return await startService()
    }

    func isServiceRunning() async -> Bool {
        let context = await installerEngine.inspectSystem()
        return context.services.kanataRunning
    }
}


