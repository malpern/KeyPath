import Foundation
import KeyPathWizardCore

/// Determines whether the wizard should force navigation to the summary page.
/// Used to prevent bouncing back to “Start Service” when the system is already healthy.
func shouldNavigateToSummary(
    currentPage: WizardPage,
    state: WizardSystemState,
    issues: [WizardIssue]
) -> Bool {
    state == .active && issues.isEmpty && currentPage != .summary
}
