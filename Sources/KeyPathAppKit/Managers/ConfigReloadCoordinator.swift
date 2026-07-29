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
    private let healthStatusProvider: @MainActor @Sendable (Int) async -> ServiceHealthStatus
    private let processLifecycleManager: ProcessLifecycleManager
    private let isRuntimeTransitioning: @MainActor @Sendable () -> Bool
    private let tcpReloadOverride: (@MainActor @Sendable () async -> TCPReloadResult)?
    private let transitionRetryMaximumPolls: Int
    private let transitionRetryWait: @MainActor @Sendable () async -> Void
    private let automaticDeferredRetriesEnabled: Bool

    // MARK: - Callbacks (set by RuntimeCoordinator after init)

    /// Called to clear stale diagnostics after a successful reload.
    var onReloadSuccess: (() -> Void)?

    // MARK: - Init

    init(
        engineClient: EngineClient,
        reloadSafetyMonitor: ReloadSafetyMonitor,
        healthStatusProvider: @escaping @MainActor @Sendable (Int) async -> ServiceHealthStatus,
        processLifecycleManager: ProcessLifecycleManager,
        isRuntimeTransitioning: @escaping @MainActor @Sendable () -> Bool = { false },
        tcpReloadOverride: (@MainActor @Sendable () async -> TCPReloadResult)? = nil,
        transitionRetryMaximumPolls: Int = Int((RuntimeStartupTiming.uiGracePeriod / 0.5).rounded(.up)),
        transitionRetryWait: @escaping @MainActor @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(500))
        },
        automaticDeferredRetriesEnabled: Bool = true
    ) {
        self.engineClient = engineClient
        self.reloadSafetyMonitor = reloadSafetyMonitor
        self.healthStatusProvider = healthStatusProvider
        self.processLifecycleManager = processLifecycleManager
        self.isRuntimeTransitioning = isRuntimeTransitioning
        self.tcpReloadOverride = tcpReloadOverride
        self.transitionRetryMaximumPolls = transitionRetryMaximumPolls
        self.transitionRetryWait = transitionRetryWait
        self.automaticDeferredRetriesEnabled = automaticDeferredRetriesEnabled
    }

    // MARK: - Reload Operations

    /// Main reload method using TCP protocol.
    /// Checks service health, permission gates, and delegates to TCP reload.
    func triggerConfigReload(
        notifyOnFailure: Bool = true,
        scheduleRetryOnPending: Bool = true
    ) async -> ReloadResult {
        // Use the manager refresh path instead of the unbounded synchronous
        // currentManagementState cache; the underlying SMAppService provider
        // still coalesces IPC with a short TTL.
        let smState = await KanataDaemonManager.shared.refreshManagementStateInternal()
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
        let healthStatus = await healthStatusProvider(PreferencesService.shared.tcpServerPort)
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
        let runtimeWasTransitioning = isRuntimeTransitioning()
        let tcpResult = await triggerTCPReload()
        if tcpResult.isSuccess {
            // Successful reload -> clear stale diagnostics
            onReloadSuccess?()
            // Notify UI that we recovered from a previous reload failure.
            NotificationCenter.default.post(name: .configReloadRecovered, object: self)
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
            if case .networkError = tcpResult,
               runtimeWasTransitioning || isRuntimeTransitioning()
            {
                AppLogger.shared.log(
                    "⏳ [Reload] Runtime transition closed the TCP reload connection; deferring until Kanata settles"
                )
                if scheduleRetryOnPending {
                    scheduleDeferredReloadAfterRuntimeTransition()
                }
                return ReloadResult(
                    success: false,
                    response: tcpResult.response,
                    errorMessage: "Kanata is restarting; reload will retry shortly",
                    protocol: .tcp,
                    disposition: .pending
                )
            }

            // Cooldown blocks are a deliberate throttle, not a real failure.
            // Schedule a deferred retry so the write we just persisted
            // actually reaches kanata, and suppress the user-facing toast/
            // error sound — the next reload attempt will fire when cooldown
            // expires. Real failures (validation, network, etc.) still
            // notify as before.
            if isCooldownBlockMessage(errorMessage) {
                if scheduleRetryOnPending {
                    scheduleDeferredReloadAfterCooldown()
                }
            } else if notifyOnFailure {
                NotificationCenter.default.post(
                    name: .configReloadFailed,
                    object: self,
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
        if isCooldownBlockMessage(message) {
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

    /// When a reload is blocked by the cooldown, we still want it to actually
    /// happen so the config file we just wrote reaches kanata. Schedule a
    /// deferred retry once the cooldown expires. Cooldown and runtime-transition
    /// retries share one task so rapid edits and overlapping recovery states
    /// coalesce into one final reload.
    private var deferredReloadTask: Task<Void, Never>?
    private var deferredReloadGeneration: UInt = 0

    private enum TransitionRetryAttempt {
        case applied
        case pending
        case rejected
    }

    private func scheduleDeferredReloadAfterCooldown() {
        deferredReloadTask?.cancel()
        deferredReloadGeneration &+= 1
        let generation = deferredReloadGeneration
        deferredReloadTask = Task { [weak self] in
            guard let self else { return }
            defer { clearDeferredReloadTask(ifGeneration: generation) }

            // 3s cooldown + a little slop so the safety check passes.
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            AppLogger.shared.log("🔁 [Reload] Firing deferred reload after cooldown expiry")
            await triggerReload()
        }
    }

    /// Wait for an intentional runtime replacement to finish, then deliver the
    /// config that was persisted while the old TCP connection was disappearing.
    /// Readiness is bounded by the same grace period used by user-facing startup UI.
    private func scheduleDeferredReloadAfterRuntimeTransition() {
        guard automaticDeferredRetriesEnabled else { return }

        deferredReloadTask?.cancel()
        deferredReloadGeneration &+= 1
        let generation = deferredReloadGeneration
        deferredReloadTask = Task { [weak self] in
            guard let self else { return }
            defer { clearDeferredReloadTask(ifGeneration: generation) }
            await retryAfterRuntimeTransition()
        }
    }

    private func clearDeferredReloadTask(ifGeneration generation: UInt) {
        guard deferredReloadGeneration == generation else { return }
        deferredReloadTask = nil
    }

    /// Poll the intentional transition and retry once the replacement runtime is healthy.
    /// The injected poll bound and wait operation keep the production grace period bounded
    /// while allowing deterministic tests without sleeping.
    @discardableResult
    func retryAfterRuntimeTransition() async -> Bool {
        for _ in 0 ..< transitionRetryMaximumPolls {
            guard !Task.isCancelled else { return false }

            switch await retryReloadIfRuntimeReady() {
            case .applied:
                return true
            case .rejected:
                return false
            case .pending:
                break
            }

            await transitionRetryWait()
        }

        guard !Task.isCancelled else { return false }
        switch await retryReloadIfRuntimeReady() {
        case .applied:
            return true
        case .rejected:
            return false
        case .pending:
            break
        }

        let message = "Kanata did not become ready after restarting; config reload was not applied"
        AppLogger.shared.warnUnlessQuietTest("⚠️ [Reload] \(message)")
        NotificationCenter.default.post(
            name: .configReloadFailed,
            object: self,
            userInfo: ["message": message, "response": ""]
        )
        return false
    }

    private func retryReloadIfRuntimeReady() async -> TransitionRetryAttempt {
        guard !isRuntimeTransitioning() else { return .pending }

        let health = await healthStatusProvider(PreferencesService.shared.tcpServerPort)
        guard health.isHealthy else { return .pending }

        AppLogger.shared.log("🔁 [Reload] Retrying config reload after runtime transition")
        let result = await triggerConfigReload(
            notifyOnFailure: false,
            scheduleRetryOnPending: false
        )
        switch result.disposition {
        case .applied:
            return .applied
        case .pending, .failed:
            return .pending
        case .rejected:
            let message = result.errorMessage ?? "Config reload was rejected"
            AppLogger.shared.warnUnlessQuietTest("⚠️ [Reload] Deferred config reload rejected: \(message)")
            NotificationCenter.default.post(
                name: .configReloadFailed,
                object: self,
                userInfo: [
                    "message": message,
                    "response": result.response ?? ""
                ]
            )
            return .rejected
        }
    }

    /// TCP-based config reload (no authentication required - see ADR-013)
    func triggerTCPReload() async -> TCPReloadResult {
        if let tcpReloadOverride {
            return await tcpReloadOverride()
        }

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
            AppLogger.shared.warnUnlessQuietTest(
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
