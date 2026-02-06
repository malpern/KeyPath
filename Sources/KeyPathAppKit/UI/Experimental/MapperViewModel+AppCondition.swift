import Foundation
import KeyPathCore

extension MapperViewModel {
    // MARK: - App Condition (Precondition) - Delegated to AppConditionManager

    /// Get list of currently running apps for the condition picker
    func getRunningApps() -> [AppConditionInfo] {
        appConditionManager.getRunningApps()
    }

    /// Open file picker to select an app for the condition (precondition)
    func pickAppCondition() {
        appConditionManager.pickAppCondition()
    }

    /// Clear the app condition
    func clearAppCondition() {
        appConditionManager.clearAppCondition()
    }

}
