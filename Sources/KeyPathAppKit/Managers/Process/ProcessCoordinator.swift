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
    private let kanataService: KanataService
    private let installerEngine: InstallerEngine
    private let privilegeBroker: PrivilegeBroker

    init(
        kanataService: KanataService = .shared,
        installerEngine: InstallerEngine = InstallerEngine(),
        privilegeBroker: PrivilegeBroker = PrivilegeBroker()
    ) {
        self.kanataService = kanataService
        self.installerEngine = installerEngine
        self.privilegeBroker = privilegeBroker
    }

    func startService() async -> Bool {
        AppLogger.shared.log("🚀 [ProcessCoordinator] Starting Kanata service via KanataService…")
        do {
            try await kanataService.start()
            await kanataService.refreshStatus()
            AppLogger.shared.log("✅ [ProcessCoordinator] KanataService start succeeded")
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.warn(
                "⚠️ [ProcessCoordinator] KanataService start failed (\(message)) - falling back to InstallerEngine repair"
            )
            let report = await installerEngine.run(intent: .repair, using: privilegeBroker)
            if report.success {
                await kanataService.refreshStatus()
                AppLogger.shared.info("✅ [ProcessCoordinator] InstallerEngine fallback start succeeded")
                return true
            } else {
                AppLogger.shared.error(
                    "❌ [ProcessCoordinator] InstallerEngine fallback start failed: \(report.failureReason ?? "Unknown error")"
                )
                return false
            }
        }
    }

    func stopService() async -> Bool {
        AppLogger.shared.log("🛑 [ProcessCoordinator] Stopping Kanata service via KanataService…")
        do {
            try await kanataService.stop()
            await kanataService.refreshStatus()
            AppLogger.shared.log("✅ [ProcessCoordinator] KanataService stop succeeded")
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.warn(
                "⚠️ [ProcessCoordinator] KanataService stop failed (\(message)) - falling back to privilege broker"
            )
            do {
                try await privilegeBroker.stopKanataService()
                await kanataService.refreshStatus()
                AppLogger.shared.info("✅ [ProcessCoordinator] Privilege broker stop fallback succeeded")
                return true
            } catch {
                AppLogger.shared.error("❌ [ProcessCoordinator] Privilege broker stop failed: \(error)")
                return false
            }
        }
    }

    func restartService() async -> Bool {
        AppLogger.shared.log("🔄 [ProcessCoordinator] Restarting Kanata service via KanataService…")
        do {
            try await kanataService.restart()
            await kanataService.refreshStatus()
            AppLogger.shared.log("✅ [ProcessCoordinator] KanataService restart succeeded")
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.warn(
                "⚠️ [ProcessCoordinator] KanataService restart failed (\(message)) - falling back to InstallerEngine repair"
            )
            let report = await installerEngine.run(intent: .repair, using: privilegeBroker)
            if report.success {
                await kanataService.refreshStatus()
                AppLogger.shared.info("✅ [ProcessCoordinator] InstallerEngine fallback restart succeeded")
                return true
            } else {
                AppLogger.shared.error(
                    "❌ [ProcessCoordinator] InstallerEngine fallback restart failed: \(report.failureReason ?? "Unknown error")"
                )
                return false
            }
        }
    }

    func isServiceRunning() async -> Bool {
        let state = await kanataService.refreshStatus()
        return state.isRunning
    }
}
