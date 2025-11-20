import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle

/// Small wrapper service to centralize health checks used by KanataManager.
/// Delegates to DiagnosticsService with the required inputs.
struct HealthCheckDecision {
    let isHealthy: Bool
    let shouldRestart: Bool
    let reason: String?
}

@MainActor
final class HealthCheckService {
    private let diagnosticsManager: DiagnosticsManaging
    private let statusProvider: () async -> (isRunning: Bool, pid: Int?)

    init(
        diagnosticsManager: DiagnosticsManaging,
        statusProvider: @escaping () async -> (isRunning: Bool, pid: Int?)
    ) {
        self.diagnosticsManager = diagnosticsManager
        self.statusProvider = statusProvider
    }

    /// Evaluate current health by querying launch daemon/process state and diagnostics.
    /// - Parameter tcpPort: The TCP port to use for diagnostics checks.
    /// - Returns: HealthCheckDecision indicating current state and whether a restart is needed.
    func evaluate(tcpPort: Int) async -> HealthCheckDecision {
        // Query launch daemon / process state
        let launchDaemonStatus = await statusProvider()
        let processStatus = ProcessHealthStatus(
            isRunning: launchDaemonStatus.isRunning,
            pid: launchDaemonStatus.pid
        )

        let status = await diagnosticsManager.checkHealth(
            processStatus: processStatus,
            tcpPort: tcpPort
        )
        return HealthCheckDecision(
            isHealthy: status.isHealthy,
            shouldRestart: status.shouldRestart,
            reason: status.reason
        )
    }

    // No additional helpers
}

// Back-compat initializer for existing call sites
extension HealthCheckService {
    convenience init(
        diagnosticsService diagnosticsManager: DiagnosticsManaging,
        processLifecycleManager: ProcessLifecycleManager
    ) {
        self.init(
            diagnosticsManager: diagnosticsManager,
            statusProvider: {
                let conflicts = await processLifecycleManager.detectConflicts()
                if let pid = conflicts.managedProcesses.first?.pid {
                    return (isRunning: true, pid: Int(pid))
                }
                if let owned = processLifecycleManager.ownedPID {
                    return (isRunning: true, pid: Int(owned))
                }
                return (isRunning: false, pid: nil)
            }
        )
    }
}
