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
  case fullRecovery  // Includes VirtualHID daemon restart
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

  private let minRestartInterval: TimeInterval = 2.0  // Base minimum time between restarts
  private let maxRestartInterval: TimeInterval = 30.0  // Maximum backoff interval
  private let backoffMultiplier: Double = 2.0  // Exponential backoff multiplier
  private let tcpServerGracePeriod: TimeInterval = 10.0  // Time to wait for TCP server to start
  private let maxConnectionFailures = 10  // VirtualHID connection failures before recovery
  private let maxStartAttempts = 5  // Max auto-start attempts before giving up (increased for backoff)
  private let maxRetryAttempts = 3  // Max retry attempts after fixes
  private let maxTCPHealthCheckRetries = 3  // Retries for TCP health checks
  private let tcpRetryDelay: TimeInterval = 0.5  // Delay between TCP retry attempts

  // MARK: - State Tracking

  private var lastStartAttempt: Date?
  private var lastServiceStart: Date?  // Tracks when service was last started (for grace period)
  private var connectionFailureCount = 0
  private var startAttemptCount = 0
  private var retryAttemptCount = 0
  private var lastHealthCheckResult: ServiceHealthStatus?

  // FIX #2: Shared TCP client for health checks to avoid creating new connections repeatedly
  private var healthCheckClient: KanataTCPClient?

  // MARK: - Initialization

  init(processLifecycle: ProcessLifecycleManager) {
    self.processLifecycle = processLifecycle
    AppLogger.shared.info("[HealthMonitor] Initialized with process lifecycle manager")
  }

  // MARK: - Health Checking

  func checkServiceHealth(
    processStatus: ProcessHealthStatus,
    tcpPort: Int
  ) async -> ServiceHealthStatus {
    AppLogger.shared.debug("[HealthMonitor] Checking service health...")

    // First check: Verify process is actually running
    guard processStatus.isRunning else {
      AppLogger.shared.warn("[HealthMonitor] Process not running")
      return ServiceHealthStatus.unhealthy(reason: "Process not running", shouldRestart: true)
    }

    AppLogger.shared.debug(
      "[HealthMonitor] Process running with PID: \(processStatus.pid?.description ?? "unknown")")

    // Check if we're in TCP grace period
    if let lastStart = lastServiceStart {
      let timeSinceStart = Date().timeIntervalSince(lastStart)
      if timeSinceStart < tcpServerGracePeriod {
        AppLogger.shared.debug(
          "[HealthMonitor] Within TCP grace period (\(String(format: "%.1f", timeSinceStart))s < \(tcpServerGracePeriod)s)"
        )
        return ServiceHealthStatus.healthy()
      }
    }

    // Second check: Try TCP health check with retries
    let tcpHealthy = await performTCPHealthCheck(port: tcpPort)

    if tcpHealthy {
      AppLogger.shared.debug("[HealthMonitor] Service is healthy")
      let status = ServiceHealthStatus.healthy()
      lastHealthCheckResult = status
      return status
    } else {
      // Check if we should wait for grace period
      if let lastStart = lastServiceStart {
        let timeSinceStart = Date().timeIntervalSince(lastStart)
        if timeSinceStart < tcpServerGracePeriod {
          AppLogger.shared.debug(
            "[HealthMonitor] TCP check failed but within grace period - giving more time"
          )
          return ServiceHealthStatus.unhealthy(
            reason: "TCP check failed (in grace period)", shouldRestart: false
          )
        }
      }

      AppLogger.shared.warn("[HealthMonitor] Service unhealthy - TCP check failed")
      let status = ServiceHealthStatus.unhealthy(
        reason: "TCP health check failed", shouldRestart: true
      )
      lastHealthCheckResult = status
      return status
    }
  }

  /// Perform TCP health check with retry logic
  private func performTCPHealthCheck(port: Int) async -> Bool {
    // FIX #2: Use shared client instead of creating new one for each health check
    // This avoids creating hundreds of TCP connections over app lifetime
    if healthCheckClient == nil {
      AppLogger.shared.debug("[HealthMonitor] Creating shared TCP health check client")
      healthCheckClient = KanataTCPClient(port: port, timeout: 3.0)
    }

    guard let client = healthCheckClient else {
      AppLogger.shared.error("[HealthMonitor] Failed to create TCP client")
      return false
    }

    var isHealthy = false

    for attempt in 1...maxTCPHealthCheckRetries {
      AppLogger.shared.debug(
        "[HealthMonitor] TCP health check attempt \(attempt)/\(maxTCPHealthCheckRetries)")

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
      AppLogger.shared.debug("[HealthMonitor] TCP health check passed")
    } else {
      AppLogger.shared.warn(
        "[HealthMonitor] TCP health check failed after \(maxTCPHealthCheckRetries) attempts")
    }

    return isHealthy
  }

  // MARK: - Restart Cooldown Management

  /// Calculate exponential backoff interval based on attempt count
  private func calculateBackoffInterval(attemptCount: Int) -> TimeInterval {
    let backoff = minRestartInterval * pow(backoffMultiplier, Double(attemptCount - 1))
    return min(backoff, maxRestartInterval)
  }

  func canRestartService() async -> RestartCooldownState {
    let now = Date()
    var canRestart = true
    var remainingCooldown: TimeInterval = 0

    // Check restart cooldown with exponential backoff
    if let lastAttempt = lastStartAttempt {
      let attemptCount = max(1, startAttemptCount)  // Ensure at least 1 for calculation
      let requiredInterval = calculateBackoffInterval(attemptCount: attemptCount)
      let timeSinceLastAttempt = now.timeIntervalSince(lastAttempt)

      if timeSinceLastAttempt < requiredInterval {
        canRestart = false
        remainingCooldown = requiredInterval - timeSinceLastAttempt
        AppLogger.shared.debug(
          "[HealthMonitor] Restart cooldown active: \(String(format: "%.1f", remainingCooldown))s remaining (attempt \(attemptCount), interval \(String(format: "%.1f", requiredInterval))s)"
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

    let backoffInterval = calculateBackoffInterval(attemptCount: startAttemptCount)
    AppLogger.shared.info(
      "[HealthMonitor] Recorded start attempt #\(startAttemptCount) (next backoff: \(String(format: "%.1f", backoffInterval))s)"
    )
  }

  func recordStartSuccess() async {
    let previousAttempts = startAttemptCount
    startAttemptCount = 0
    retryAttemptCount = 0
    connectionFailureCount = 0
    AppLogger.shared.info(
      "[HealthMonitor] Recorded start success - reset counters (was at \(previousAttempts) attempts)"
    )
  }

  func recordStartFailure() async {
    let backoffInterval = calculateBackoffInterval(attemptCount: startAttemptCount)
    AppLogger.shared.warn(
      "[HealthMonitor] Recorded start failure (attempt \(startAttemptCount), next backoff: \(String(format: "%.1f", backoffInterval))s)"
    )
  }

  // MARK: - Connection Failure Tracking

  func recordConnectionFailure() async -> Bool {
    connectionFailureCount += 1
    AppLogger.shared.debug(
      "[HealthMonitor] Connection failure #\(connectionFailureCount)/\(maxConnectionFailures)"
    )

    let shouldTriggerRecovery = connectionFailureCount >= maxConnectionFailures
    if shouldTriggerRecovery {
      AppLogger.shared.warn("[HealthMonitor] Max connection failures reached - recovery needed")
    }

    return shouldTriggerRecovery
  }

  func recordConnectionSuccess() async {
    if connectionFailureCount > 0 {
      AppLogger.shared.info("[HealthMonitor] Connection restored - resetting failure count")
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
      AppLogger.shared.error(
        "[HealthMonitor] Max start attempts (\(maxStartAttempts)) reached - giving up"
      )
      return .giveUp(reason: "Failed to start after \(maxStartAttempts) attempts")
    }

    if retryAttemptCount >= maxRetryAttempts {
      AppLogger.shared.error(
        "[HealthMonitor] Max retry attempts (\(maxRetryAttempts)) reached - giving up"
      )
      return .giveUp(reason: "Failed to recover after \(maxRetryAttempts) retry attempts")
    }

    // Check if connection failures warrant full recovery
    if connectionFailureCount >= maxConnectionFailures {
      AppLogger.shared.warn(
        "[HealthMonitor] Connection failures detected - recommend full recovery")
      return .fullRecovery
    }

    // Check process conflicts
    let conflicts = await processLifecycle.detectConflicts()
    if conflicts.hasConflicts {
      AppLogger.shared.warn(
        "[HealthMonitor] Process conflicts detected - recommend kill and restart")
      return .killAndRestart
    }

    // Default to simple restart
    AppLogger.shared.debug("[HealthMonitor] Recommend simple restart")
    return .simpleRestart
  }

  func resetMonitoringState() async {
    lastStartAttempt = nil
    lastServiceStart = nil
    connectionFailureCount = 0
    startAttemptCount = 0
    retryAttemptCount = 0
    lastHealthCheckResult = nil

    // FIX #2: Clean up shared health check client
    if let client = healthCheckClient {
      await client.cancelInflightAndCloseConnection()
      healthCheckClient = nil
      AppLogger.shared.debug("[HealthMonitor] Closed shared TCP health check client")
    }

    AppLogger.shared.info("[HealthMonitor] Reset all monitoring state")
  }
}
