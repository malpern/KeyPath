import Foundation
import KeyPathCore

/// Manages diagnostics and health monitoring
@MainActor
final class DiagnosticsManager {
    private var diagnostics: [KanataDiagnostic] = []
    private let healthMonitor: ServiceHealthMonitor
    private let processStatusProvider: @MainActor @Sendable () async -> ProcessHealthStatus

    init(
        healthMonitor: ServiceHealthMonitor,
        processStatusProvider: @escaping @MainActor @Sendable () async -> ProcessHealthStatus
    ) {
        self.healthMonitor = healthMonitor
        self.processStatusProvider = processStatusProvider
    }

    func addDiagnostic(_ diagnostic: KanataDiagnostic) {
        diagnostics.append(diagnostic)
        AppLogger.shared.log(
            "\(diagnostic.severity.emoji) [DiagnosticsManager] \(diagnostic.title): \(diagnostic.description)"
        )

        // Keep only last 50 diagnostics to prevent memory bloat
        if diagnostics.count > 50 {
            diagnostics.removeFirst(diagnostics.count - 50)
        }
    }

    func getDiagnostics() -> [KanataDiagnostic] {
        diagnostics
    }

    func clearDiagnostics() {
        diagnostics.removeAll()
    }

    func checkHealth() async -> ServiceHealthStatus {
        let processStatus = await processStatusProvider()
        return await healthMonitor.checkServiceHealth(processStatus: processStatus)
    }

    func recordGrabFailureAndDecideRecovery() async -> GrabRecoveryDecision {
        await healthMonitor.recordGrabFailureAndDecideRecovery()
    }

    func recordGrabSuccess() async {
        await healthMonitor.recordGrabSuccess()
    }
}
