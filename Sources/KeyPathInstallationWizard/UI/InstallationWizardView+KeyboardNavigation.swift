import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - Keyboard Navigation

    /// Navigate to the previous page using keyboard left arrow
    public func navigateToPreviousPage() {
        guard stateMachine.currentPage != .summary else { return }
        let defaultSequence: [WizardPage] = [
            .fullDiskAccess, .conflicts, .inputMonitoring, .accessibility,
            .karabinerComponents, .service, .communication
        ]
        let sequence = navSequence.isEmpty ? defaultSequence : navSequence
        guard let idx = sequence.firstIndex(of: stateMachine.currentPage), idx > 0 else {
            return
        }
        let previousPage = sequence[idx - 1]
        stateMachine.navigateToPage(previousPage)
        AppLogger.shared.log("⬅️ [Keyboard] Navigated to previous page: \(previousPage.displayName)")
    }

    /// Navigate to the next page using keyboard right arrow, respecting prerequisites
    public func navigateToNextPage() {
        guard stateMachine.currentPage != .summary else { return }
        Task { @MainActor in
            if let next = await stateMachine.getNextPage(
                for: stateMachine.wizardState,
                issues: stateMachine.wizardIssues
            ) {
                stateMachine.navigateToPage(next)
                AppLogger.shared.log("➡️ [Keyboard] Navigated to next page: \(next.displayName)")
            }
        }
    }
}
