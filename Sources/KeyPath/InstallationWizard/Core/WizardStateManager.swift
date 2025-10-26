import Foundation

@MainActor
class WizardStateManager: ObservableObject {
    // 🎯 NEW: Use SystemValidator instead of SystemStatusChecker
    private var validator: SystemValidator?

    func configure(kanataManager: KanataManager) {
        // Create validator backed by ProcessService to avoid direct
        // dependencies on ProcessLifecycleManager in wizard code.
        let processService = ProcessService(lifecycle: ProcessLifecycleManager(kanataManager: kanataManager))
        validator = SystemValidator(
            processLifecycleManager: processService,
            kanataManager: kanataManager
        )
        AppLogger.shared.log("🎯 [WizardStateManager] Configured with NEW SystemValidator (Phase 2)")
    }

    func detectCurrentState() async -> SystemStateResult {
        guard let validator else {
            return SystemStateResult(
                state: .initializing,
                issues: [],
                autoFixActions: [],
                detectionTimestamp: Date()
            )
        }

        // 🎯 NEW: Use SystemValidator and adapt to old format
        AppLogger.shared.log("🎯 [WizardStateManager] Using SystemValidator (Phase 2)")
        let snapshot = await validator.checkSystem()
        return SystemSnapshotAdapter.adapt(snapshot)
    }
}
