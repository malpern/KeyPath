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
    // 🎯 Phase 6+: Prefer RuntimeCoordinator façade over direct InstallerEngine usage
    private weak var kanataManager: RuntimeCoordinator?

    // Cache for the last known wizard state
    var lastWizardSnapshot: WizardSnapshotRecord?

    func configure(kanataManager: RuntimeCoordinator) {
        self.kanataManager = kanataManager
        AppLogger.shared.log("🎯 [WizardStateManager] Configured with RuntimeCoordinator façade")
    }

    func detectCurrentState(progressCallback _: @escaping @Sendable (Double) -> Void = { _ in }) async
        -> SystemStateResult {
        if let manager = kanataManager {
            AppLogger.shared.log("🎯 [WizardStateManager] Using RuntimeCoordinator.inspectSystemContext()")
            let context = await manager.inspectSystemContext()
            return SystemContextAdapter.adapt(context)
        } else {
            AppLogger.shared.warn("⚠️ [WizardStateManager] RuntimeCoordinator not configured; falling back to InstallerEngine.inspectSystem()")
            let context = await InstallerEngine().inspectSystem()
            return SystemContextAdapter.adapt(context)
        }
    }
}
