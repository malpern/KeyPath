import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle

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

/// Tracks restart attempts and cooldown state
struct RestartCooldownState: Sendable {
    let canRestart: Bool
    let remainingCooldown: TimeInterval
    let attemptsSinceLastSuccess: Int
    let isInGracePeriod: Bool
}

/// Recovery action recommendation based on health status
enum ServiceRecoveryAction: Sendable {
    case none
    case simpleRestart
    case killAndRestart
    case fullRecovery // Includes VirtualHID daemon restart
    case giveUp(reason: String)
}

// MARK: - Protocol

/// Protocol for service health monitoring and recovery strategies
@MainActor
protocol ServiceHealthMonitorProtocol: AnyObject {
    /// Check if the service is currently healthy
    /// - Parameters:
    ///   - processStatus: The current process status from LaunchDaemon
    ///   - tcpPort: TCP port for health checks
    /// - Returns: Health status with recommendation
    func checkServiceHealth(
        processStatus: ProcessHealthStatus,
        tcpPort: Int
    ) async -> ServiceHealthStatus

    /// Check if a restart is allowed based on cooldown state
    /// - Returns: Cooldown state indicating if restart is allowed
    func canRestartService() async -> RestartCooldownState

    /// Record that a service start was attempted
    /// - Parameter timestamp: When the start was attempted
    func recordStartAttempt(timestamp: Date) async

    /// Record that a service start succeeded
    func recordStartSuccess() async

    /// Record that a service start failed
    func recordStartFailure() async

    /// Record a connection failure (for VirtualHID monitoring)
    /// - Returns: True if max failures reached and recovery should be triggered
    func recordConnectionFailure() async -> Bool

    /// Record a successful connection (resets failure count)
    func recordConnectionSuccess() async

    /// Determine the appropriate recovery action based on current state
    /// - Parameter healthStatus: Current health status
    /// - Returns: Recommended recovery action
    func determineRecoveryAction(healthStatus: ServiceHealthStatus) async -> ServiceRecoveryAction

    /// Reset all monitoring state (e.g., after successful recovery)
    func resetMonitoringState() async
}

// MARK: - Process Status Type

/// Simple process status for health monitoring
struct ProcessHealthStatus: Sendable {
    let isRunning: Bool
    let pid: Int?
}

// MARK: - Implementation

/// Monitors service health and manages restart cooldowns and recovery strategies
@MainActor
final class ServiceHealthMonitor: ServiceHealthMonitorProtocol {
    // MARK: - Dependencies

    private let processLifecycle: ProcessLifecycleManager

    // MARK: - Configuration Constants

    private let minRestartInterval: TimeInterval = 2.0 // Minimum time between restarts
    private let tcpServerGracePeriod: TimeInterval = 10.0 // Time to wait for TCP server to start
    private let maxConnectionFailures = 10 // VirtualHID connection failures before recovery
    private let maxStartAttempts = 2 // Max auto-start attempts before giving up
    private let maxRetryAttempts = 3 // Max retry attempts after fixes
    private let maxTCPHealthCheckRetries = 3 // Retries for TCP health checks
    private let tcpRetryDelay: TimeInterval = 0.5 // Delay between TCP retry attempts

    // MARK: - State Tracking

    private var lastStartAttempt: Date?
    private var lastServiceStart: Date? // Tracks when service was last started (for grace period)
    private var connectionFailureCount = 0
    private var startAttemptCount = 0
    private var retryAttemptCount = 0
    private var lastHealthCheckResult: ServiceHealthStatus?

    // MARK: - Initialization

    init(processLifecycle: ProcessLifecycleManager) {
        self.processLifecycle = processLifecycle
        AppLogger.shared.log("🏥 [HealthMonitor] Initialized with process lifecycle manager")
    }

    // MARK: - Health Checking

    func checkServiceHealth(
        processStatus: ProcessHealthStatus,
        tcpPort: Int
    ) async -> ServiceHealthStatus {
        AppLogger.shared.log("🏥 [HealthMonitor] Checking service health...")

        // First check: Verify process is actually running
        guard processStatus.isRunning else {
            AppLogger.shared.log("🏥 [HealthMonitor] Process not running")
            return ServiceHealthStatus.unhealthy(reason: "Process not running", shouldRestart: true)
        }

        AppLogger.shared.log("🏥 [HealthMonitor] Process running with PID: \(processStatus.pid?.description ?? "unknown")")

        // Check if we're in TCP grace period
        if let lastStart = lastServiceStart {
            let timeSinceStart = Date().timeIntervalSince(lastStart)
            if timeSinceStart < tcpServerGracePeriod {
                AppLogger.shared.log(
                    "🏥 [HealthMonitor] Within TCP grace period (\(String(format: "%.1f", timeSinceStart))s < \(tcpServerGracePeriod)s)"
                )
                return ServiceHealthStatus.healthy()
            }
        }

        // Second check: Try TCP health check with retries
        let tcpHealthy = await performTCPHealthCheck(port: tcpPort)

        if tcpHealthy {
            AppLogger.shared.log("🏥 [HealthMonitor] Service is healthy")
            let status = ServiceHealthStatus.healthy()
            lastHealthCheckResult = status
            return status
        } else {
            // Check if we should wait for grace period
            if let lastStart = lastServiceStart {
                let timeSinceStart = Date().timeIntervalSince(lastStart)
                if timeSinceStart < tcpServerGracePeriod {
                    AppLogger.shared.log(
                        "🏥 [HealthMonitor] TCP check failed but within grace period - giving more time"
                    )
                    return ServiceHealthStatus.unhealthy(reason: "TCP check failed (in grace period)", shouldRestart: false)
                }
            }

            AppLogger.shared.log("🏥 [HealthMonitor] Service unhealthy - TCP check failed")
            let status = ServiceHealthStatus.unhealthy(reason: "TCP health check failed", shouldRestart: true)
            lastHealthCheckResult = status
            return status
        }
    }

    /// Perform TCP health check with retry logic
    private func performTCPHealthCheck(port: Int) async -> Bool {
        var isHealthy = false

        for attempt in 1 ... maxTCPHealthCheckRetries {
            AppLogger.shared.log("🏥 [HealthMonitor] TCP health check attempt \(attempt)/\(maxTCPHealthCheckRetries)")

            let client = KanataTCPClient(port: port, timeout: 3.0)
            isHealthy = await client.checkServerStatus()
            if isHealthy {
                break
            }

            // Brief pause between retries
            if attempt < maxTCPHealthCheckRetries {
                try? await Task.sleep(nanoseconds: UInt64(tcpRetryDelay * 1_000_000_000))
            }
        }

        if isHealthy {
            AppLogger.shared.log("🏥 [HealthMonitor] TCP health check passed")
        } else {
            AppLogger.shared.log("🏥 [HealthMonitor] TCP health check failed after \(maxTCPHealthCheckRetries) attempts")
        }

        return isHealthy
    }

    // MARK: - Restart Cooldown Management

    func canRestartService() async -> RestartCooldownState {
        let now = Date()
        var canRestart = true
        var remainingCooldown: TimeInterval = 0

        // Check restart cooldown
        if let lastAttempt = lastStartAttempt {
            let timeSinceLastAttempt = now.timeIntervalSince(lastAttempt)
            if timeSinceLastAttempt < minRestartInterval {
                canRestart = false
                remainingCooldown = minRestartInterval - timeSinceLastAttempt
                AppLogger.shared.log(
                    "🏥 [HealthMonitor] Restart cooldown active: \(String(format: "%.1f", remainingCooldown))s remaining"
                )
            }
        }

        // Check if we're in grace period
        var isInGracePeriod = false
        if let lastStart = lastServiceStart {
            let timeSinceStart = now.timeIntervalSince(lastStart)
            isInGracePeriod = timeSinceStart < tcpServerGracePeriod
        }

        return RestartCooldownState(
            canRestart: canRestart,
            remainingCooldown: remainingCooldown,
            attemptsSinceLastSuccess: startAttemptCount,
            isInGracePeriod: isInGracePeriod
        )
    }

    func recordStartAttempt(timestamp: Date) async {
        lastStartAttempt = timestamp
        lastServiceStart = timestamp
        startAttemptCount += 1
        AppLogger.shared.log("🏥 [HealthMonitor] Recorded start attempt #\(startAttemptCount)")
    }

    func recordStartSuccess() async {
        startAttemptCount = 0
        retryAttemptCount = 0
        connectionFailureCount = 0
        AppLogger.shared.log("🏥 [HealthMonitor] Recorded start success - reset counters")
    }

    func recordStartFailure() async {
        AppLogger.shared.log("🏥 [HealthMonitor] Recorded start failure (attempt \(startAttemptCount))")
    }

    // MARK: - Connection Failure Tracking

    func recordConnectionFailure() async -> Bool {
        connectionFailureCount += 1
        AppLogger.shared.log(
            "🏥 [HealthMonitor] Connection failure #\(connectionFailureCount)/\(maxConnectionFailures)"
        )

        let shouldTriggerRecovery = connectionFailureCount >= maxConnectionFailures
        if shouldTriggerRecovery {
            AppLogger.shared.log("🏥 [HealthMonitor] Max connection failures reached - recovery needed")
        }

        return shouldTriggerRecovery
    }

    func recordConnectionSuccess() async {
        if connectionFailureCount > 0 {
            AppLogger.shared.log("🏥 [HealthMonitor] Connection restored - resetting failure count")
            connectionFailureCount = 0
        }
    }

    // MARK: - Recovery Strategy

    func determineRecoveryAction(healthStatus: ServiceHealthStatus) async -> ServiceRecoveryAction {
        // If healthy, no action needed
        guard !healthStatus.isHealthy || healthStatus.shouldRestart else {
            return .none
        }

        // Check if we've exceeded max attempts
        if startAttemptCount >= maxStartAttempts {
            AppLogger.shared.log(
                "🏥 [HealthMonitor] Max start attempts (\(maxStartAttempts)) reached - giving up"
            )
            return .giveUp(reason: "Failed to start after \(maxStartAttempts) attempts")
        }

        if retryAttemptCount >= maxRetryAttempts {
            AppLogger.shared.log(
                "🏥 [HealthMonitor] Max retry attempts (\(maxRetryAttempts)) reached - giving up"
            )
            return .giveUp(reason: "Failed to recover after \(maxRetryAttempts) retry attempts")
        }

        // Check if connection failures warrant full recovery
        if connectionFailureCount >= maxConnectionFailures {
            AppLogger.shared.log("🏥 [HealthMonitor] Connection failures detected - recommend full recovery")
            return .fullRecovery
        }

        // Check process conflicts
        let conflicts = await processLifecycle.detectConflicts()
        if conflicts.hasConflicts {
            AppLogger.shared.log("🏥 [HealthMonitor] Process conflicts detected - recommend kill and restart")
            return .killAndRestart
        }

        // Default to simple restart
        AppLogger.shared.log("🏥 [HealthMonitor] Recommend simple restart")
        return .simpleRestart
    }

    func resetMonitoringState() async {
        lastStartAttempt = nil
        lastServiceStart = nil
        connectionFailureCount = 0
        startAttemptCount = 0
        retryAttemptCount = 0
        lastHealthCheckResult = nil
        AppLogger.shared.log("🏥 [HealthMonitor] Reset all monitoring state")
    }
}
