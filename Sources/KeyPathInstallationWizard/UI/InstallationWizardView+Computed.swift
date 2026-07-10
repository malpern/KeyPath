import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

public extension InstallationWizardView {
    // MARK: - Computed Properties

    func getBuildTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        // Use compile time if available, otherwise current time
        return formatter.string(from: Date())
    }

    func handlePageChange(from oldPage: WizardPage, to newPage: WizardPage) {
        AppLogger.shared.log("🧭 [Wizard] View detected page change: \(oldPage) → \(newPage)")
        if newPage == .summary, !isValidating {
            refreshSystemState(showSpinner: true, previousPage: oldPage)
        }
    }
}

// MARK: - Extracted Components

// KeyboardNavigationModifier -> Components/KeyboardNavigationModifier.swift
// WizardOperations.stateDetection -> Core/WizardOperationsUIExtension.swift
// AutoFixActionDescriptions -> Core/AutoFixActionDescriptions.swift

// MARK: - Focus Ring Suppression Helper

public extension InstallationWizardView {
    /// Recursively disable focus rings in all subviews
    func disableFocusRings(in view: NSView) {
        view.focusRingType = .none
        for subview in view.subviews {
            disableFocusRings(in: subview)
        }
    }
}
