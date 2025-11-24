import Foundation
import KeyPathCore

/// Small wrapper service to centralize health checks used by RuntimeCoordinator.
/// Delegates to DiagnosticsService with the required inputs.
struct HealthCheckDecision {
    let isHealthy: Bool
    let shouldRestart: Bool
    let reason: String?
}

@MainActor
final class HealthCheckService {
    private let diagnosticsManager: DiagnosticsManaging

    init(diagnosticsManager: DiagnosticsManaging) {
        self.diagnosticsManager = diagnosticsManager
    }

    /// Evaluate current health by querying launch daemon/process state and diagnostics.
    /// - Parameter tcpPort: The TCP port to use for diagnostics checks.
    /// - Returns: HealthCheckDecision indicating current state and whether a restart is needed.
    func evaluate(tcpPort: Int) async -> HealthCheckDecision {
        let status = await diagnosticsManager.checkHealth(tcpPort: tcpPort)
        return HealthCheckDecision(
            isHealthy: status.isHealthy,
            shouldRestart: status.shouldRestart,
            reason: status.reason
        )
    }
}
