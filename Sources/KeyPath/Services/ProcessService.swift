import Foundation

/// ProcessService: thin facade over process lifecycle operations
///
/// Phase 2 Task 1 scaffolding. This service will encapsulate all start/stop/
/// health/cleanup behavior currently spread across KanataManager and
/// ProcessLifecycleManager. Initial commit is a no‑logic wrapper to enable
/// incremental migration without risk.
@MainActor
final class ProcessService: @unchecked Sendable {
    // Dependencies (existing types)
    private let lifecycle: ProcessLifecycleManager

    init(lifecycle: ProcessLifecycleManager = ProcessLifecycleManager()) {
        self.lifecycle = lifecycle
    }

    // MARK: - Lifecyle façade (to be expanded as we migrate)

    func registerStartedProcess(pid: pid_t, command: String) async {
        await lifecycle.registerStartedProcess(pid: pid, command: command)
    }

    func unregisterProcess() async {
        await lifecycle.unregisterProcess()
    }

    func detectConflicts() async -> ProcessLifecycleManager.ConflictResolution {
        await lifecycle.detectConflicts()
    }

    func terminateExternalProcesses() async throws {
        try await lifecycle.terminateExternalProcesses()
    }

    func cleanupOrphansIfNeeded() async {
        await lifecycle.cleanupOrphanedProcesses()
    }

    func invalidatePIDCache() async {
        await lifecycle.invalidatePIDCache()
    }
}

