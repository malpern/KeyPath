import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

public extension InstallationWizardView {
    func getCurrentOperationName() -> String {
        if fixInFlight { return String(localized: "Applying Fix...") }
        if isValidating { return String(localized: "Detecting System State") }
        return String(localized: "Processing...")
    }

    func getCurrentOperationProgress() -> Double {
        0.0
    }

    func isCurrentOperationIndeterminate() -> Bool {
        true
    }
}
