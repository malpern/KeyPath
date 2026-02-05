import Foundation
import KeyPathCore

extension RuntimeCoordinator {
    // MARK: - Conflict Resolution

    /// Prompt the user to resolve a rule conflict via the UI
    @MainActor
    func promptForConflictResolution(_ context: RuleConflictContext) async -> RuleConflictChoice? {
        // Cancel any pending resolution to avoid continuation leak
        conflictResolutionContinuation?.resume(returning: nil)
        conflictResolutionContinuation = nil

        pendingRuleConflict = context
        notifyStateChanged()

        return await withCheckedContinuation { continuation in
            conflictResolutionContinuation = continuation
        }
    }

    /// Called by ViewModel when user makes a choice in the conflict resolution dialog
    func resolveConflict(with choice: RuleConflictChoice?) {
        pendingRuleConflict = nil
        conflictResolutionContinuation?.resume(returning: choice)
        conflictResolutionContinuation = nil
        notifyStateChanged()
    }
}
