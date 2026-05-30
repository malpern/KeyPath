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

    func dismissAndRefreshMainScreen() {
        stopLoginItemsApprovalPolling()

        Task { @MainActor in
            NotificationCenter.default.post(name: .wizardStartupRevalidate, object: nil)
            dismiss()
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
