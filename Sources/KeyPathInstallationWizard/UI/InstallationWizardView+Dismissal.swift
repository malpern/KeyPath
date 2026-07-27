import KeyPathCore
import KeyPathWizardCore
import SwiftUI

public extension InstallationWizardView {
    func handleCloseButtonTapped() {
        let criticalIssues = stateMachine.wizardIssues.filter { $0.severity == .critical }

        if criticalIssues.isEmpty {
            forceInstantClose()
        } else {
            showingCloseConfirmation = true
        }
    }

    func forceInstantClose() {
        dismissAndRefreshMainScreen()
    }

    @MainActor
    func dismissAndRefreshMainScreen() {
        stopLoginItemsApprovalPolling()

        let shouldShowFirstSuccess = if onFirstSuccess == nil {
            false
        } else {
            FirstSuccessOnboardingGate.isEligible(
                didShowWelcomePage: didShowWelcomePage,
                wizardState: stateMachine.wizardState,
                issues: stateMachine.wizardIssues
            )
        }

        NotificationCenter.default.post(name: .wizardStartupRevalidate, object: nil)
        dismiss()
        if shouldShowFirstSuccess {
            onFirstSuccess?()
        }
    }

    func performBackgroundCleanup() {}

    func forciblyCloseWizard() {
        isForceClosing = true

        Task { @MainActor in
            asyncOperationManager.cancelAllOperationsAsync()
            isValidating = false
        }

        refreshTask?.cancel()
        stopLoginItemsApprovalPolling()
        dismiss()
    }
}
