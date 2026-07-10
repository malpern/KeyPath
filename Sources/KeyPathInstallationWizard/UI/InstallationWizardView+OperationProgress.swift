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
}
