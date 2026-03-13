import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions

/// Manages configuration reload operations via TCP.
///
/// Extracted from `RuntimeCoordinator+Configuration.swift` to give config reload
/// its own focused type. `RuntimeCoordinator` delegates all reload calls here.
@MainActor
final class ConfigReloadCoordinator {
    // MARK: - Dependencies

    private let engineClient: EngineClient
    private let reloadSafetyMonitor: ReloadSafetyMonitor
    private let diagnosticsManager: DiagnosticsManaging
    private let processLifecycleManager: ProcessLifecycleManager

    // MARK: - Callbacks (set by RuntimeCoordinator after init)

    /// Called to clear stale diagnostics after a successful reload.
    var onReloadSuccess: (() -> Void)?

    // MARK: - Init

    init(
        engineClient: EngineClient,
        reloadSafetyMonitor: ReloadSafetyMonitor,
        diagnosticsManager: DiagnosticsManaging,
        processLifecycleManager: ProcessLifecycleManager
    ) {
        self.engineClient = engineClient
        self.reloadSafetyMonitor = reloadSafetyMonitor
        self.diagnosticsManager = diagnosticsManager
        self.processLifecycleManager = processLifecycleManager
    }

    // MARK: - Reload Operations

    /// Main reload method using TCP protocol.
    /// Checks service health, permission gates, and delegates to TCP reload.
    func triggerConfigReload() async -> ReloadResult {
        // Use cached state to avoid synchronous IPC to SMAppService in hot path
        let smState: KanataDaemonManager.ServiceManagementState
        let cached = await MainActor.run { KanataDaemonManager.shared.currentManagementState }
        if cached == .unknown {
            smState = await KanataDaemonManager.shared.refreshManagementStateInternal()
        } else {
            smState = cached
        }
        if smState == .smappservicePending {
            AppLogger.shared.warn(
                "⚠️ [Reload] Skipping TCP reload because SMAppService requires approval"
            )
            return ReloadResult(
                success: false,
                response: nil,
                errorMessage: "Approve KeyPath in Login Items before reloading config",
                protocol: nil
            )
        }

        // Skip reloads if Kanata service isn't healthy yet
        let healthStatus = await diagnosticsManager.checkHealth(
            tcpPort: PreferencesService.shared.tcpServerPort
        )
        if !healthStatus.isHealthy {
            AppLogger.shared.warn(
                "⚠️ [Reload] Skipping TCP reload because Kanata service is not healthy yet: \(healthStatus.reason ?? "unknown reason")"
            )
            return ReloadResult(
                success: false,
                response: nil,
                errorMessage: healthStatus.reason ?? "Kanata service is starting; retry shortly",
                protocol: nil
            )
        }

        // Phase 2: Just-in-time permission gating for reload
        if FeatureFlags.useJustInTimePermissionRequests {
            var allowed = false
            await PermissionGate.shared.checkAndRequestPermissions(
                for: .configurationReload,
                onGranted: { allowed = true },
                onDenied: { allowed = false }
            )
            if !allowed {
                AppLogger.shared.warn("⚠️ [Reload] Blocked by missing permission (JIT gate)")
                return ReloadResult(
                    success: false, response: nil, errorMessage: "Permission required", protocol: nil
                )
            }
        }

        // Try TCP reload
        AppLogger.shared.debug("📡 [Reload] Attempting TCP reload")
        let tcpResult = await triggerTCPReload()
        if tcpResult.isSuccess {
            // Successful reload -> clear stale diagnostics
            onReloadSuccess?()
            // Notify UI that we recovered from a previous reload failure.
            NotificationCenter.default.post(name: .configReloadRecovered, object: nil)
            return ReloadResult(
                success: true,
                response: tcpResult.response ?? "",
                errorMessage: nil,
                protocol: .tcp
            )
        } else {
            AppLogger.shared.debug(
                "📡 [Reload] TCP reload failed: \(tcpResult.errorMessage ?? "Unknown error")"
            )
            NotificationCenter.default.post(
                name: .configReloadFailed,
                object: nil,
                userInfo: [
                    "message": tcpResult.errorMessage ?? "TCP reload failed",
                    "response": tcpResult.response ?? "",
                ]
            )
            return ReloadResult(
                success: false,
                response: tcpResult.response,
                errorMessage: tcpResult.errorMessage ?? "TCP reload failed",
                protocol: .tcp
            )
        }
    }

    /// TCP-based config reload (no authentication required - see ADR-013)
    func triggerTCPReload() async -> TCPReloadResult {
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug("🧪 [TCP Reload] Skipping TCP reload in test environment")
            return .networkError("Test environment - TCP disabled")
        }

        // Check reload safety first
        let currentPID = processLifecycleManager.ownedPID
        let safetyCheck = await reloadSafetyMonitor.checkReloadSafety(
            currentPID: currentPID.map { Int($0) }
        )

        if !safetyCheck.isSafe {
            let reason = safetyCheck.reason ?? "Safety check failed"
            AppLogger.shared.warn("⛔️ [TCP Reload] Reload blocked by safety monitor: \(reason)")
            return .networkError("Reload blocked: \(reason)")
        }

        AppLogger.shared.log("📡 [TCP Reload] Triggering config reload via EngineClient (TCP)")
        let res = await engineClient.reloadConfig()
        let mapped = mapEngineToTCP(res)

        // Record the reload attempt for safety monitoring
        await reloadSafetyMonitor.recordReloadAttempt(
            succeeded: mapped.isSuccess,
            daemonPID: currentPID.map { Int($0) }
        )

        return mapped
    }

    /// Main reload method that should be used by new code
    func triggerReload() async {
        let result = await triggerConfigReload()
        if !result.isSuccess {
            AppLogger.shared.warn(
                "⚠️ [Reload] Reload failed (no automatic restart): \(result.errorMessage ?? "Unknown")"
            )
        }
    }

    // MARK: - Private Helpers

    private func mapEngineToTCP(_ result: EngineReloadResult) -> TCPReloadResult {
        switch result {
        case let .success(response: resp): .success(response: resp)
        case let .failure(error: err, response: resp): .failure(error: err, response: resp)
        case let .networkError(err): .networkError(err)
        }
    }
}
