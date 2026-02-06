import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - Operation Progress Helpers

    func getCurrentOperationName() -> String {
        // Get the first running operation and provide a user-friendly name
        guard let operationId = asyncOperationManager.runningOperations.first else {
            return "Processing..."
        }

        if operationId.contains("auto_fix_terminateConflictingProcesses") {
            return "Terminating Conflicting Processes"
        } else if operationId.contains("auto_fix_installMissingComponents") {
            return "Installing Missing Components"
        } else if operationId.contains("auto_fix_activateVHIDDeviceManager") {
            return "Activating Driver Extensions"
        } else if operationId.contains("auto_fix_installBundledKanata") {
            return "Installing Kanata binary"
        } else if operationId.contains("auto_fix_startKarabinerDaemon") {
            return "Starting System Daemon"
        } else if operationId.contains("auto_fix_restartVirtualHIDDaemon") {
            return "Restarting Virtual HID Daemon"
        } else if operationId.contains("auto_fix_installLaunchDaemonServices") {
            return "Installing Launch Services"
        } else if operationId.contains("auto_fix_createConfigDirectories") {
            return "Creating Configuration Directories"
        } else if operationId.contains("state_detection") {
            return "Detecting System State"
        } else if operationId.contains("start_service") {
            return "Starting Kanata Service"
        } else if operationId.contains("grant_permission") {
            return "Waiting for Permission Grant"
        } else if operationId.contains("auto_fix_restartUnhealthyServices") {
            return "Restarting Failing Services"
        } else {
            return "Processing Operation"
        }
    }

    func getCurrentOperationProgress() -> Double {
        guard let operationId = asyncOperationManager.runningOperations.first else {
            return 0.0
        }
        return asyncOperationManager.getProgress(operationId)
    }

    func isCurrentOperationIndeterminate() -> Bool {
        // Most operations provide progress, but some like permission grants are indeterminate
        guard let operationId = asyncOperationManager.runningOperations.first else {
            return true
        }

        return operationId.contains("grant_permission") || operationId.contains("state_detection")
    }

    /// Get detailed error message for specific auto-fix failures
    func getDetailedErrorMessage(for action: AutoFixAction, actionDescription _: String)
        async -> String
    {
        AppLogger.shared.log("🔍 [ErrorMessage] getDetailedErrorMessage called for action: \(action)")

        var message = AutoFixActionDescriptions.errorMessage(for: action)

        // Enrich daemon-related errors with a succinct diagnosis
        if action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon {
            let detail = await kanataManager.getVirtualHIDBreakageSummary()
            if !detail.isEmpty {
                message += "\n\n" + detail
            }
        }

        AppLogger.shared.log("🔍 [ErrorMessage] Returning message: \(message)")
        return message
    }
}
