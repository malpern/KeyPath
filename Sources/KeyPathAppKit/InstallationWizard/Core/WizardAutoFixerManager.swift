import Foundation
import KeyPathCore
import KeyPathWizardCore
import Observation

/// Manager wrapper for WizardAutoFixer that provides configuration and delegation
///
/// This class serves as an @Observable wrapper around WizardAutoFixer,
/// allowing lazy configuration after view initialization.
@MainActor
@Observable
class WizardAutoFixerManager {
    private(set) var autoFixer: WizardAutoFixer?

    func configure(
        kanataManager: RuntimeCoordinator,
        toastManager _: WizardToastManager,
        statusReporter: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        AppLogger.shared.log("🔧 [AutoFixerManager] Configuring with RuntimeCoordinator")
        autoFixer = WizardAutoFixer(
            kanataManager: kanataManager,
            statusReporter: statusReporter
        )
        AppLogger.shared.log("🔧 [AutoFixerManager] Configuration complete")
    }

    func canAutoFix(_ action: AutoFixAction) -> Bool {
        autoFixer?.canAutoFix(action) ?? false
    }

    func performAutoFix(_ action: AutoFixAction) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixerManager] performAutoFix called for action: \(action)")
        guard let autoFixer else {
            AppLogger.shared.log("❌ [AutoFixerManager] Internal autoFixer is nil - returning false")
            return false
        }
        AppLogger.shared.log("🔧 [AutoFixerManager] Delegating to internal autoFixer")
        return await autoFixer.performAutoFix(action)
    }
}
