import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore

struct WizardSnapshotRecord {
    let state: WizardSystemState
    let issues: [WizardIssue]
}

@MainActor
class WizardStateManager: ObservableObject {
    // 🎯 NEW: Use InstallerEngine façade instead of SystemValidator directly
    private var installerEngine = InstallerEngine()
    
    // Cache for the last known wizard state
    var lastWizardSnapshot: WizardSnapshotRecord?

    func configure(kanataManager: RuntimeCoordinator) {
        // Recreate InstallerEngine with live RuntimeCoordinator so state detection can
        // trust the active TCP connection instead of treating Kanata as stopped.
        installerEngine = InstallerEngine(kanataManager: kanataManager)
        AppLogger.shared.log(
            "🎯 [WizardStateManager] Configured with InstallerEngine façade (Phase 6.7)")
    }

    func detectCurrentState(progressCallback _: @escaping @Sendable (Double) -> Void = { _ in }) async
        -> SystemStateResult {
        // 🎯 NEW: Use InstallerEngine.inspectSystem() and adapt to old format
        AppLogger.shared.log("🎯 [WizardStateManager] Using InstallerEngine.inspectSystem() (Phase 6.7)")
        let context = await installerEngine.inspectSystem()
        // Note: progressCallback is not supported by InstallerEngine yet
        // This is acceptable as inspectSystem() is fast enough
        return SystemContextAdapter.adapt(context)
    }
}
