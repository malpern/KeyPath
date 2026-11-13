import Foundation
import KeyPathCore

// MARK: - Health Check Result Types

/// Result of a service health check
struct ServiceHealthStatus: Sendable {
    let isHealthy: Bool
    let reason: String?
    let shouldRestart: Bool
    let timestamp: Date

    static func healthy() -> ServiceHealthStatus {
        ServiceHealthStatus(
            isHealthy: true,
            reason: nil,
            shouldRestart: false,
            timestamp: Date()
        )
    }

    static func unhealthy(reason: String, shouldRestart: Bool = true) -> ServiceHealthStatus {
        ServiceHealthStatus(
            isHealthy: false,
            reason: reason,
            shouldRestart: shouldRestart,
            timestamp: Date()
        )
    }
}

// MARK: - Grab Recovery Decision

/// Outcome of a kanata input-grab-failure event: attempt a bounded recovery, or give
/// up after exhausting attempts (so a deterministic crash doesn't restart forever).
enum GrabRecoveryDecision: Equatable, Sendable {
    /// Attempt recovery now; `attempt` is the 1-based attempt number in this episode.
    case recover(attempt: Int)
    /// Recovery budget exhausted — surface a persistent error instead of restarting again.
    case giveUp(attempts: Int)
}

// MARK: - Process Status Type

/// Simple process status for health monitoring
struct ProcessHealthStatus: Sendable {
    let isRunning: Bool
    let pid: Int?
}

// MARK: - Implementation

/// Checks that the engine is running and answering, and bounds recovery from
/// input-grab failures.
@MainActor
final class ServiceHealthMonitor {
    // MARK: - Configuration Constants

    private let maxTCPHealthCheckRetries = 3 // Retries for TCP health checks
    private let tcpRetryDelay: TimeInterval = 0.5 // Delay between TCP retry attempts

    // MARK: - State Tracking

    // Grab-failure recovery guard (#625): bound auto-restarts so a deterministic kanata
    // crash (e.g. #631) doesn't restart forever. Attempts reset on grab-success or after
    // a quiet window (a fresh failure episode gets a fresh budget).
    private let maxGrabRecoveryAttempts = 3
    private let grabRecoveryEpisodeWindow: TimeInterval = 300 // 5 min
    private var grabRecoveryAttempts = 0
    private var lastGrabRecoveryAt: Date?

    /// FIX #2: Shared TCP client for health checks to avoid creating new connections repeatedly
    private var healthCheckClient: KanataTCPClient?

    /// Track EventListener heartbeat to avoid redundant TCP connections
    private var lastHeartbeatTime: Date?
    private var heartbeatObserver: NotificationCenter.ObservationToken?
    private let heartbeatFreshnessThreshold: TimeInterval = 5.0

    // MARK: - Initialization

    init() {
        heartbeatObserver = NotificationCenter.default.addObserver(for: KanataHeartbeat.self) { [weak self] _ in
            self?.lastHeartbeatTime = Date()
        }
        AppLogger.shared.info("[HealthMonitor] Initialized")
    }

    // MARK: - Health Checking

    func checkServiceHealth(processStatus: ProcessHealthStatus) async -> ServiceHealthStatus {
        AppLogger.shared.debug("[HealthMonitor] Checking service health...")

        // First check: Verify process is actually running
        guard processStatus.isRunning else {
            AppLogger.shared.warnUnlessQuietTest("[HealthMonitor] Process not running")
            return ServiceHealthStatus.unhealthy(reason: "Process not running", shouldRestart: true)
        }

        AppLogger.shared.debug(
            "[HealthMonitor] Process running with PID: \(processStatus.pid?.description ?? "unknown")"
        )

        // Second check: Try TCP health check with retries
        let tcpHealthy = await performTCPHealthCheck()

        if tcpHealthy {
            AppLogger.shared.debug("[HealthMonitor] Service is healthy")
            return ServiceHealthStatus.healthy()
        }
        AppLogger.shared.warn("[HealthMonitor] Service unhealthy - TCP check failed")
        return ServiceHealthStatus.unhealthy(reason: "TCP health check failed", shouldRestart: true)
    }

    /// Perform TCP health check with retry logic
    private func performTCPHealthCheck() async -> Bool {
        // Skip real TCP checks in test environment to avoid timeouts
        guard !TestEnvironment.isRunningTests else {
            AppLogger.shared.debug("[HealthMonitor] TCP health check skipped in test environment")
            return true // Assume healthy in tests
        }

        // Fast path: if EventListener recently received data, TCP is healthy.
        // This avoids opening a redundant TCP connection that can disrupt EventListener's stream.
        if let lastBeat = lastHeartbeatTime,
           Date().timeIntervalSince(lastBeat) < heartbeatFreshnessThreshold
        {
            AppLogger.shared.debug("[HealthMonitor] TCP healthy (recent EventListener heartbeat)")
            return true
        }

        // Slow path: no recent heartbeat, fall back to direct TCP check
        // (e.g., during startup before EventListener connects)

        // FIX #2: Use shared client instead of creating new one for each health check
        // This avoids creating hundreds of TCP connections over app lifetime
        if healthCheckClient == nil {
            AppLogger.shared.debug("[HealthMonitor] Creating shared TCP health check client")
            healthCheckClient = KanataTCPClient(timeout: 3.0)
        }

        guard let client = healthCheckClient else {
            AppLogger.shared.error("[HealthMonitor] Failed to create TCP client")
            return false
        }

        var isHealthy = false

        for attempt in 1 ... maxTCPHealthCheckRetries {
            AppLogger.shared.debug(
                "[HealthMonitor] TCP health check attempt \(attempt)/\(maxTCPHealthCheckRetries)"
            )

            isHealthy = await client.checkServerStatus()

            if isHealthy {
                break
            }

            // Brief pause between retries
            if attempt < maxTCPHealthCheckRetries {
                try? await Task.sleep(for: .seconds(tcpRetryDelay))
            }
        }

        if isHealthy {
            AppLogger.shared.debug("[HealthMonitor] TCP health check passed")
        } else {
            AppLogger.shared.warn(
                "[HealthMonitor] TCP health check failed after \(maxTCPHealthCheckRetries) attempts"
            )
        }

        return isHealthy
    }

    func recordGrabFailureAndDecideRecovery() async -> GrabRecoveryDecision {
        decideGrabRecovery(now: Date())
    }

    /// Testable core of the grab-recovery guard (injectable clock).
    func decideGrabRecovery(now: Date) -> GrabRecoveryDecision {
        // Start a fresh episode (fresh budget) if enough quiet time passed since the
        // last recovery attempt — a failure long after a previous burst isn't the same
        // crash loop.
        if let last = lastGrabRecoveryAt, now.timeIntervalSince(last) > grabRecoveryEpisodeWindow {
            grabRecoveryAttempts = 0
        }
        guard grabRecoveryAttempts < maxGrabRecoveryAttempts else {
            AppLogger.shared.errorUnlessQuietTest(
                "[HealthMonitor] kanata input-grab still failing after \(grabRecoveryAttempts) recovery attempts — giving up (manual intervention / reboot likely needed)"
            )
            return .giveUp(attempts: grabRecoveryAttempts)
        }
        grabRecoveryAttempts += 1
        lastGrabRecoveryAt = now
        AppLogger.shared.warnUnlessQuietTest(
            "[HealthMonitor] kanata input-grab failure — recovery attempt \(grabRecoveryAttempts)/\(maxGrabRecoveryAttempts)"
        )
        return .recover(attempt: grabRecoveryAttempts)
    }

    func recordGrabSuccess() async {
        if grabRecoveryAttempts > 0 {
            AppLogger.shared.info("[HealthMonitor] Keyboard grab restored — resetting grab-recovery attempts")
            grabRecoveryAttempts = 0
            lastGrabRecoveryAt = nil
        }
    }
}
