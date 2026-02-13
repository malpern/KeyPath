import ApplicationServices
import Foundation
import IOKit.hidsystem
import KeyPathCore
import KeyPathDaemonLifecycle

// MARK: - RuntimeCoordinator Configuration Extension

extension RuntimeCoordinator {
    // MARK: - Configuration Initialization

    func createInitialConfigIfNeeded() async {
        do {
            try await configurationService.createInitialConfigIfNeeded()
        } catch {
            AppLogger.shared.error(
                "❌ [Config] Failed to create initial config via ConfigurationService: \(error)"
            )
        }
    }

    /// Public wrapper to ensure a default user config exists.
    /// Returns true if the config exists after this call.
    func createDefaultUserConfigIfMissing() async -> Bool {
        await configurationManager.createDefaultIfMissing()
    }

    // MARK: - Configuration Validation

    func validateConfigFile() async -> (isValid: Bool, errors: [String]) {
        await configurationManager.validateConfigFile()
    }

    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws
        -> String
    {
        try await configurationManager.backupFailedConfigAndApplySafe(
            failedConfig: failedConfig,
            mappings: mappings
        )
    }

    // MARK: - Hot Reload via TCP

    /// Main reload method using TCP protocol
    func triggerConfigReload() async -> ReloadResult {
        // Skip reloads if SMAppService is awaiting approval; avoid long TCP timeouts
        let smState = await KanataDaemonManager.shared.refreshManagementState()
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

        // Skip reloads if Kanata service isn't healthy yet; avoid connection-refused storm
        let healthStatus = await kanataService.checkHealth(
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
            // Successful reload -> clear stale diagnostics (e.g., Invalid Configuration)
            clearDiagnostics()
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
            // Reliability-first: do NOT restart Kanata just because a config reload failed.
            // Restarts create a remapping gap and can make typing sporadic.
            //
            // Callers can decide whether to retry or escalate to a restart based on explicit
            // engine health checks (process exited, TCP unreachable, etc).
            NotificationCenter.default.post(
                name: .configReloadFailed,
                object: nil,
                userInfo: [
                    "message": tcpResult.errorMessage ?? "TCP reload failed",
                    "response": tcpResult.response ?? ""
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

    private func mapEngineToTCP(_ result: EngineReloadResult) -> TCPReloadResult {
        switch result {
        case let .success(response: resp): .success(response: resp)
        case let .failure(error: err, response: resp): .failure(error: err, response: resp)
        case let .networkError(err): .networkError(err)
        }
    }

    /// Main reload method that should be used by new code
    func triggerReload() async {
        let result = await triggerConfigReload()
        if !result.isSuccess {
            // Keep the engine running; surface the error in logs and let the caller decide how to recover.
            AppLogger.shared.warn(
                "⚠️ [Reload] Reload failed (no automatic restart): \(result.errorMessage ?? "Unknown")"
            )
        }
    }
}

// MARK: - Result Types

/// TCP reload result
struct ReloadResult {
    let success: Bool
    let response: String?
    let errorMessage: String?
    let `protocol`: CommunicationProtocol?

    var isSuccess: Bool {
        success
    }
}
