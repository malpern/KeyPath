import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    public func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            let fallbackURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
            NSWorkspace.shared.openApplication(
                at: fallbackURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil
            )
        }
    }

    /// Start polling for Login Items approval status change
    public func startLoginItemsApprovalPolling() {
        stopLoginItemsApprovalPolling()

        AppLogger.shared.log("🔍 [LoginItems] Starting approval polling (3 min timeout)...")

        loginItemsPollingTask = Task { @MainActor in
            let maxAttempts = 90
            for attempt in 1 ... maxAttempts {
                guard !Task.isCancelled else {
                    AppLogger.shared.log("🔍 [LoginItems] Polling cancelled")
                    return
                }

                let state = await WizardDependencies.daemonManager?.refreshManagementState()
                if attempt % 10 == 1 {
                    AppLogger.shared.log("🔍 [LoginItems] Poll #\(attempt)/\(maxAttempts): state=\(state?.description ?? "nil")")
                }

                if state == .smappserviceActive {
                    AppLogger.shared.log("✅ [LoginItems] Approval detected at poll #\(attempt)! Refreshing wizard state...")

                    await MainActor.run {
                        showingBackgroundApprovalPrompt = false
                        toastManager.showSuccess("KeyPath approved in Login Items")
                    }

                    refreshSystemState()
                    return
                }

                _ = await WizardSleep.seconds(2)
            }

            AppLogger.shared.log("⏰ [LoginItems] Polling timed out after 3 minutes")
            toastManager.showInfo("Login Items check timed out. Click refresh to check again.")
        }
    }

    /// Stop polling for Login Items approval
    public func stopLoginItemsApprovalPolling() {
        loginItemsPollingTask?.cancel()
        loginItemsPollingTask = nil
    }
}
