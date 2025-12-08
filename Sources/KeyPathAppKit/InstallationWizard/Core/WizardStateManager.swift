import Foundation
import KeyPathDaemonLifecycle
import KeyPathWizardCore

/// Lightweight cache for wizard state between open/close cycles.
/// Used to show last known state while loading fresh data.
struct WizardSnapshotRecord {
    let state: WizardSystemState
    let issues: [WizardIssue]
}

/// Simple cache container for the last known wizard state.
/// This enables showing the previous state while loading fresh data.
@MainActor
class WizardStateManager: ObservableObject {
    /// Cache for the last known wizard state
    var lastWizardSnapshot: WizardSnapshotRecord?

    /// Configure is called during wizard setup (no-op but retained for existing call sites)
    func configure(kanataManager _: RuntimeCoordinator) {
        // No longer needs configuration - kept for API compatibility
    }
}
