import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - Keyboard Navigation

    /// Navigate to the previous page using keyboard left arrow
    func navigateToPreviousPage() {
        guard stateMachine.currentPage != .summary else { return }
        let defaultSequence: [WizardPage] = [
            .fullDiskAccess, .conflicts, .inputMonitoring, .accessibility,
            .karabinerComponents, .kanataComponents, .service, .communication
        ]
        let sequence = navSequence.isEmpty ? defaultSequence : navSequence
        guard let idx = sequence.firstIndex(of: stateMachine.currentPage), idx > 0 else {
            return
        }
        let previousPage = sequence[idx - 1]
        stateMachine.navigateToPage(previousPage)
        AppLogger.shared.log("⬅️ [Keyboard] Navigated to previous page: \(previousPage.displayName)")
    }

    /// Navigate to the next page using keyboard right arrow
    func navigateToNextPage() {
        guard stateMachine.currentPage != .summary else { return }
        let defaultSequence: [WizardPage] = [
            .fullDiskAccess, .conflicts, .inputMonitoring, .accessibility,
            .karabinerComponents, .kanataComponents, .service, .communication
        ]
        let sequence = navSequence.isEmpty ? defaultSequence : navSequence
        guard let idx = sequence.firstIndex(of: stateMachine.currentPage),
              idx < sequence.count - 1
        else { return }
        let nextPage = sequence[idx + 1]
        stateMachine.navigateToPage(nextPage)
        AppLogger.shared.log("➡️ [Keyboard] Navigated to next page: \(nextPage.displayName)")
    }

}
