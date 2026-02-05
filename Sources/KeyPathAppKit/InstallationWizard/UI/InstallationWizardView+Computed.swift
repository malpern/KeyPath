import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - Computed Properties

    func getBuildTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        // Use compile time if available, otherwise current time
        return formatter.string(from: Date())
    }

    /// Quick summary to surface state when a fix times out
    func describeServiceState() async -> String {
        let state = await KanataDaemonManager.shared.refreshManagementState()
        let vhidRunning = await VHIDDeviceManager().detectRunning()
        return "VHID running=\(vhidRunning ? "yes" : "no"); services=\(state.description)"
    }
}

// MARK: - Extracted Components

// KeyboardNavigationModifier -> Components/KeyboardNavigationModifier.swift
// WizardOperations.stateDetection -> Core/WizardOperationsUIExtension.swift
// AutoFixActionDescriptions -> Core/AutoFixActionDescriptions.swift

// MARK: - Focus Ring Suppression Helper

extension InstallationWizardView {
    /// Recursively disable focus rings in all subviews
    func disableFocusRings(in view: NSView) {
        view.focusRingType = .none
        for subview in view.subviews {
            disableFocusRings(in: subview)
        }
    }
}
