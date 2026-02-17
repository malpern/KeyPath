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

    /// Navigate to the next page using keyboard right arrow, skipping green pages
    func navigateToNextPage() {
        guard stateMachine.currentPage != .summary else { return }
        let defaultSequence: [WizardPage] = [
            .fullDiskAccess, .conflicts, .inputMonitoring, .accessibility,
            .karabinerComponents, .kanataComponents, .service, .communication
        ]
        let sequence = navSequence.isEmpty ? defaultSequence : navSequence
        guard let idx = sequence.firstIndex(of: stateMachine.currentPage) else { return }

        // Advance past green pages to find the next page with issues
        var candidateIdx = idx + 1
        while candidateIdx < sequence.count {
            let candidate = sequence[candidateIdx]
            if stateMachine.navigationEngine.pageHasRelevantIssues(
                candidate,
                issues: stateMachine.wizardIssues,
                state: stateMachine.wizardState
            ) {
                stateMachine.navigateToPage(candidate)
                AppLogger.shared.log("➡️ [Keyboard] Navigated to next page: \(candidate.displayName)")
                return
            }
            candidateIdx += 1
        }
        // All remaining pages are green — no navigation
    }
}
