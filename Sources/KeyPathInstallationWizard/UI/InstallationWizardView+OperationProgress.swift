import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

public extension InstallationWizardView {
    func getCurrentOperationName() -> String {
        if fixInFlight { return "Applying Fix..." }
        if isValidating { return "Detecting System State" }
        return "Processing..."
    }

    func getCurrentOperationProgress() -> Double {
        0.0
    }

    func isCurrentOperationIndeterminate() -> Bool {
        true
    }

    func getDetailedErrorMessage(for action: AutoFixAction, actionDescription _: String)
        async -> String
    {
        var message = AutoFixActionDescriptions.errorMessage(for: action)

        if action == .restartVirtualHIDDaemon || action == .startKarabinerDaemon {
            if let detail = await kanataManager?.getVirtualHIDBreakageSummary(), !detail.isEmpty {
                message += "\n\n" + detail
            }
        }

        return message
    }
}
