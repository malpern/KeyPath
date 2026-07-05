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
                protocol: nil,
                disposition: .pending
            )
        }

        // Skip reloads if Kanata service isn't healthy yet
        let healthStatus = await diagnosticsManager.checkHealth(
            tcpPort: PreferencesService.shared.tcpServerPort
        )
        if !healthStatus.isHealthy {
            AppLogger.shared.warnUnlessQuietTest(
                "⚠️ [Reload] Skipping TCP reload because Kanata service is not healthy yet: \(healthStatus.reason ?? "unknown reason")"
            )
            return ReloadResult(
                success: false,
                response: nil,
                errorMessage: healthStatus.reason ?? "Kanata service is starting; retry shortly",
                protocol: nil,
                disposition: .pending
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
                    success: false, response: nil, errorMessage: "Permission required", protocol: nil, disposition: .rejected
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
                protocol: .tcp,
                disposition: .applied
            )
        } else {
            AppLogger.shared.debug(
                "📡 [Reload] TCP reload failed: \(tcpResult.errorMessage ?? "Unknown error")"
            )
            let errorMessage = tcpResult.errorMessage ?? "TCP reload failed"
            // Cooldown blocks are a deliberate throttle, not a real failure.
            // Schedule a deferred retry so the write we just persisted
            // actually reaches kanata, and suppress the user-facing toast/
            // error sound — the next reload attempt will fire when cooldown
            // expires. Real failures (validation, network, etc.) still
            // notify as before.
            if isDeferredReloadMessage(errorMessage) {
                scheduleDeferredReload(for: errorMessage)
            } else {
                NotificationCenter.default.post(
                    name: .configReloadFailed,
                    object: nil,
                    userInfo: [
                        "message": errorMessage,
                        "response": tcpResult.response ?? ""
                    ]
                )
            }
            return ReloadResult(
                success: false,
                response: tcpResult.response,
                errorMessage: errorMessage,
                protocol: .tcp,
                disposition: disposition(for: tcpResult, message: errorMessage)
            )
        }
    }

    private func disposition(for tcpResult: TCPReloadResult, message: String) -> ReloadDisposition {
        if isDeferredReloadMessage(message) {
            return .pending
        }

        switch tcpResult {
        case .failure:
            return .rejected
        case .networkError:
            return .failed
        case .success:
            return .applied
        }
    }

    /// True if the error came from the 3s reload-cooldown throttle rather
    /// than a real failure.
    private func isCooldownBlockMessage(_ message: String) -> Bool {
        message.contains("Reload blocked") && message.contains("cooldown")
    }

    /// Connection closure/reset can happen during launch while kanata is
    /// restarting around a freshly deployed app. Treat it like a pending reload:
    /// retry quietly instead of showing a scary toast for a transient startup race.
    private func isTransientConnectionMessage(_ message: String) -> Bool {
        message.contains("Connection closed") || message.contains("reset by peer")
    }

    private func isDeferredReloadMessage(_ message: String) -> Bool {
        isCooldownBlockMessage(message) || isTransientConnectionMessage(message)
    }

    /// When a reload is deferred, we still want it to actually happen so the
    /// config file we just wrote reaches kanata. Schedule a retry; de-duped via
    /// a single outstanding task so rapid edits coalesce into one final reload.
    private var deferredReloadTask: Task<Void, Never>?

    private func scheduleDeferredReload(for message: String) {
        deferredReloadTask?.cancel()
        let isCooldown = isCooldownBlockMessage(message)
        let delayNanoseconds: UInt64 = isCooldown ? 3_200_000_000 : 1_000_000_000
        deferredReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            AppLogger.shared.log("🔁 [Reload] Firing deferred reload after pending condition: \(message)")
            await triggerReload()
            deferredReloadTask = nil
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
        if !result.isSuccess, result.disposition != .pending {
            AppLogger.shared.warnUnlessQuietTest(
                "⚠️ [Reload] Reload failed (no automatic restart): \(result.errorMessage ?? "Unknown")"
            )
        } else if result.disposition == .pending {
            AppLogger.shared.debug(
                "ℹ️ [Reload] Reload pending retry: \(result.errorMessage ?? "Unknown")"
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
