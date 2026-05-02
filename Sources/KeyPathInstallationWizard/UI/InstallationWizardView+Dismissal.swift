import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    public func handleCloseButtonTapped() {
        asyncOperationManager.cancelAllOperationsAsync()

        let criticalIssues = stateMachine.wizardIssues.filter { $0.severity == .critical }

        if criticalIssues.isEmpty {
            forceInstantClose()
        } else {
            showingCloseConfirmation = true
        }
    }

    /// Force immediate wizard dismissal
    public func forceInstantClose() {
        dismissAndRefreshMainScreen()
    }

    /// Dismiss wizard and trigger main screen validation refresh
    public func dismissAndRefreshMainScreen() {
        stopLoginItemsApprovalPolling()

        Task { @MainActor in
            NotificationCenter.default.post(name: .wizardStartupRevalidate, object: nil)
            AppLogger.shared.log("🔄 [Wizard] Triggered StartupValidator refresh before dismiss")
            dismiss()
        }
    }

    /// Performs cancellation and cleanup in the background after UI dismissal
    public func performBackgroundCleanup() {
        Task { @MainActor [weak asyncOperationManager] in
            asyncOperationManager?.cancelAllOperationsAsync()
        }
    }

    /// Nuclear option: Force wizard closed immediately
    public func forciblyCloseWizard() {
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Starting nuclear shutdown at \(Date())")

        isForceClosing = true
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Force closing flag set - no new operations allowed")

        AppLogger.shared.log("🔴 [FORCE-CLOSE] Clearing operation state...")
        Task { @MainActor in
            asyncOperationManager.runningOperations.removeAll()
            asyncOperationManager.operationProgress.removeAll()
            isValidating = false
            AppLogger.shared.log("🔴 [FORCE-CLOSE] Operation state cleared")
            AppLogger.shared.flushBuffer()
        }

        AppLogger.shared.log("🔴 [FORCE-CLOSE] Cancelling refresh task...")
        refreshTask?.cancel()
        stopLoginItemsApprovalPolling()

        AppLogger.shared.log("🔴 [FORCE-CLOSE] Calling dismiss()...")
        AppLogger.shared.flushBuffer()
        dismiss()

        Task { @MainActor [weak asyncOperationManager] in
            asyncOperationManager?.cancelAllOperationsAsync()
            AppLogger.shared.log("🔴 [FORCE-CLOSE] Background cleanup completed")
            AppLogger.shared.flushBuffer()
        }
    }
}
