import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore

@MainActor
class WizardStateManager: ObservableObject {
    // 🎯 NEW: Use InstallerEngine façade instead of SystemValidator directly
    private let installerEngine = InstallerEngine()

    func configure(kanataManager _: KanataManager) {
        // InstallerEngine doesn't need KanataManager for inspectSystem()
        // It creates its own SystemValidator internally
        AppLogger.shared.log("🎯 [WizardStateManager] Configured with InstallerEngine façade (Phase 6.7)")
    }

    func detectCurrentState(progressCallback: @escaping @Sendable (Double) -> Void = { _ in }) async -> SystemStateResult {
        // 🎯 NEW: Use InstallerEngine.inspectSystem() and adapt to old format
        AppLogger.shared.log("🎯 [WizardStateManager] Using InstallerEngine.inspectSystem() (Phase 6.7)")
        let context = await installerEngine.inspectSystem()
        // Note: progressCallback is not supported by InstallerEngine yet
        // This is acceptable as inspectSystem() is fast enough
        return SystemContextAdapter.adapt(context)
    }
}
