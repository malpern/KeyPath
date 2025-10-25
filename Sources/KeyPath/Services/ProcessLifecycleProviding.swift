import Foundation

/// Minimal interface required by health monitoring to reason about process conflicts.
@MainActor
protocol ProcessLifecycleProviding: AnyObject {
    func detectConflicts() async -> ProcessLifecycleManager.ConflictResolution
}

// Adopt the protocol for existing types without changing their public API.
extension ProcessLifecycleManager: ProcessLifecycleProviding {}

