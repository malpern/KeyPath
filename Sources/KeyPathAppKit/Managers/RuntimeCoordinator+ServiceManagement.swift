import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuntimeCoordinator {
    /// Starts Kanata with VirtualHID connection validation
    func startKanataWithValidation() async {
        await recoveryCoordinator.startKanataWithValidation(
            isKarabinerDaemonRunning: { await isKarabinerDaemonRunning() },
            startKanata: { await startKanata(reason: "VirtualHID validation start") },
            onError: { [weak self] error in
                self?.lastError = error
                self?.notifyStateChanged()
            }
        )
    }

    // MARK: - Service Management Helpers

    @discardableResult
    func startKanata(reason: String = "Manual start") async -> Bool {
        AppLogger.shared.log("🚀 [Service] Starting Kanata (\(reason))")

        // CRITICAL: Check VHID daemon health before starting Kanata
        // If Kanata starts without a healthy VHID daemon, it will grab keyboard input
        // but have nowhere to output keystrokes, freezing the keyboard
        if await !isKarabinerDaemonRunning() {
            AppLogger.shared.error("❌ [Service] Cannot start Kanata - VirtualHID daemon is not running")
            lastError = "Cannot start: Karabiner VirtualHID daemon is not running. Please complete the setup wizard."
            notifyStateChanged()
            return false
        }

        do {
            try await kanataService.start()
            await kanataService.refreshStatus()

            // Start the app context service for per-app keymaps
            // This monitors frontmost app and activates virtual keys via TCP
            await AppContextService.shared.start()

            lastError = nil
            notifyStateChanged()
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error("❌ [Service] Start failed: \(message)")
            lastError = "Start failed: \(message)"
            notifyStateChanged()
            return false
        }
    }

    @discardableResult
    func stopKanata(reason: String = "Manual stop") async -> Bool {
        AppLogger.shared.log("🛑 [Service] Stopping Kanata (\(reason))")

        // Stop the app context service first
        await AppContextService.shared.stop()

        do {
            try await kanataService.stop()
            await kanataService.refreshStatus()
            notifyStateChanged()
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error("❌ [Service] Stop failed: \(message)")
            lastError = "Stop failed: \(message)"
            notifyStateChanged()
            return false
        }
    }

    @discardableResult
    func restartKanata(reason: String = "Manual restart") async -> Bool {
        await restartServiceWithFallback(reason: reason)
    }

    func currentServiceState() async -> KanataService.ServiceState {
        await kanataService.refreshStatus()
    }

    @discardableResult
    func restartServiceWithFallback(reason: String) async -> Bool {
        AppLogger.shared.log("🔄 [ServiceRestart] \(reason) - delegating to ProcessCoordinator")
        let restarted = await processCoordinator.restartService()

        let state = await kanataService.refreshStatus()
        let isRunning = state.isRunning

        if restarted, isRunning {
            AppLogger.shared.log("✅ [ServiceRestart] Kanata is running (state=\(state.description))")
            notifyStateChanged()
            return true
        }

        if !restarted {
            AppLogger.shared.warn("⚠️ [ServiceRestart] ProcessCoordinator restart failed")
        } else {
            AppLogger.shared.warn("⚠️ [ServiceRestart] Restart finished but state=\(state.description)")
        }
        notifyStateChanged()
        return false
    }

    // Check if permission issues should trigger the wizard
    func shouldShowWizardForPermissions() async -> Bool {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        return snapshot.blockingIssue != nil
    }

    // MARK: - UI-Focused Lifecycle Methods (from SimpleRuntimeCoordinator)

    /// Check if this is a fresh install (no Kanata binary or config)
    func isFirstTimeInstall() -> Bool {
        installationCoordinator.isFirstTimeInstall(configPath: KeyPathConstants.Config.mainConfigPath)
    }
}
