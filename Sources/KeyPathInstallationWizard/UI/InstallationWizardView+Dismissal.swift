import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    public func handleCloseButtonTapped() {
        let criticalIssues = stateMachine.wizardIssues.filter { $0.severity == .critical }

        if criticalIssues.isEmpty {
            forceInstantClose()
        } else {
            showingCloseConfirmation = true
        }
    }

    public func forceInstantClose() {
        dismissAndRefreshMainScreen()
    }

    public func dismissAndRefreshMainScreen() {
        stopLoginItemsApprovalPolling()

        Task { @MainActor in
            NotificationCenter.default.post(name: .wizardStartupRevalidate, object: nil)
            dismiss()
        }
    }

    public func performBackgroundCleanup() {}

    public func forciblyCloseWizard() {
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
