import Foundation
import KeyPathCore

extension RuntimeCoordinator {
    // MARK: - SaveCoordinatorDelegate

    func saveStatusDidChange(_ status: SaveStatus) {
        saveStatus = status
    }

    func configDidUpdate(mappings: [KeyMapping]) {
        applyKeyMappings(mappings)
    }

    // MARK: - UI State Snapshot (Phase 4: MVVM - delegates to StatePublisherService)

    /// Configure state publisher (called during init)
    func configureStatePublisher() {
        statePublisher.configure { [weak self] in
            self?.buildUIState() ?? KanataUIState.empty
        }
    }

    /// Notify observers that state has changed
    /// Call this after any operation that modifies UI-visible state
    func notifyStateChanged() {
        statePublisher.notifyStateChanged()
    }

    /// Refresh process running state from system (call after service operations)
    /// This is more efficient than checking on every UI state sync
    func refreshProcessState() {
        notifyStateChanged()
    }

    /// Returns a snapshot of current UI state for ViewModel synchronization
    /// This method allows KanataViewModel to read UI state without @Published properties
    func getCurrentUIState() -> KanataUIState {
        buildUIState()
    }

    /// Build the current UI state snapshot
    func buildUIState() -> KanataUIState {
        // Sync diagnostics from DiagnosticsManager
        diagnostics = diagnosticsManager.getDiagnostics()

        // Debug: Log custom rules count when building state
        AppLogger.shared.log("📊 [RuntimeCoordinator] buildUIState: customRules.count = \(customRules.count)")
        if let error = lastError {
            AppLogger.shared.debug("🚨 [RuntimeCoordinator] buildUIState: lastError = \(error)")
        }

        return KanataUIState(
            // Core Status
            lastError: lastError,
            lastWarning: lastWarning,
            keyMappings: keyMappings,
            ruleCollections: ruleCollections,
            customRules: customRules,
            currentLayerName: currentLayerName,
            diagnostics: diagnostics,
            lastProcessExitCode: lastProcessExitCode,
            lastConfigUpdate: lastConfigUpdate,

            // Validation & Save Status
            validationError: validationError,
            saveStatus: saveStatus,

            // Rule conflict resolution
            pendingRuleConflict: pendingRuleConflict
        )
    }
}
