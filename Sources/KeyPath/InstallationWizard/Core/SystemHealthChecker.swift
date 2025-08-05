import Foundation

/// Responsible for checking the functional health of system services
/// This goes beyond process existence to verify actual functionality
class SystemHealthChecker {
  private let kanataManager: KanataManager
  private let vhidDeviceManager: VHIDDeviceManager

  init(kanataManager: KanataManager, vhidDeviceManager: VHIDDeviceManager) {
    self.kanataManager = kanataManager
    self.vhidDeviceManager = vhidDeviceManager
  }

  // MARK: - Service Health Detection

  /// Checks if Kanata service is not just running, but actually functioning correctly
  func isKanataServiceFunctional() async -> Bool {
    // If Kanata isn't running, it's definitely not functional
    guard kanataManager.isRunning else {
      AppLogger.shared.log("🔍 [HealthChecker] Kanata not running - not functional")
      return false
    }

    // Check if there are active diagnostics indicating problems
    let hasActiveErrors = kanataManager.diagnostics.contains { diagnostic in
      diagnostic.severity == .error
        && (diagnostic.category == .conflict || diagnostic.category == .permissions
          || diagnostic.category == .process)
    }

    if hasActiveErrors {
      AppLogger.shared.log("🔍 [HealthChecker] Kanata has active error diagnostics - not functional")
      return false
    }

    // Use VirtualHID connection health as a proxy for Kanata functionality
    // If VirtualHID connection is unhealthy, Kanata isn't truly functional
    let vhidHealth = vhidDeviceManager.detectConnectionHealth()
    if !vhidHealth {
      AppLogger.shared.log(
        "🔍 [HealthChecker] VirtualHID connection unhealthy - Kanata not functional")
      return false
    }

    AppLogger.shared.log("🔍 [HealthChecker] Kanata service appears functional")
    return true
  }

  /// Checks if VirtualHID daemon is both running and healthy
  func isVirtualHIDHealthy() -> Bool {
    let status = vhidDeviceManager.getDetailedStatus()
    let isHealthy = status.isFullyOperational

    AppLogger.shared.log("🔍 [HealthChecker] VirtualHID health status: \(isHealthy)")
    AppLogger.shared.log("🔍 [HealthChecker] \(status.description)")

    return isHealthy
  }

  /// Checks if Karabiner daemon is running and functioning
  func isKarabinerDaemonHealthy() -> Bool {
    let isRunning = kanataManager.isKarabinerDaemonRunning()

    // For now, we only check if it's running
    // Could be enhanced to check daemon health via logs or other mechanisms
    AppLogger.shared.log("🔍 [HealthChecker] Karabiner daemon health: \(isRunning)")

    return isRunning
  }

  /// Comprehensive system health check
  func performSystemHealthCheck() async -> SystemHealthStatus {
    let kanataFunctional = await isKanataServiceFunctional()
    let vhidHealthy = isVirtualHIDHealthy()
    let daemonHealthy = isKarabinerDaemonHealthy()

    let overallHealthy = kanataFunctional && vhidHealthy && daemonHealthy

    return SystemHealthStatus(
      kanataServiceFunctional: kanataFunctional,
      virtualHIDHealthy: vhidHealthy,
      karabinerDaemonHealthy: daemonHealthy,
      overallHealthy: overallHealthy
    )
  }
}

// MARK: - Supporting Types

/// Comprehensive system health status
struct SystemHealthStatus {
  let kanataServiceFunctional: Bool
  let virtualHIDHealthy: Bool
  let karabinerDaemonHealthy: Bool
  let overallHealthy: Bool

  /// Description for logging and debugging
  var description: String {
    """
    System Health Status:
    - Kanata Service Functional: \(kanataServiceFunctional)
    - VirtualHID Healthy: \(virtualHIDHealthy)
    - Karabiner Daemon Healthy: \(karabinerDaemonHealthy)
    - Overall Healthy: \(overallHealthy)
    """
  }
}
