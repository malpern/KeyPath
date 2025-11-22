import Foundation
import KeyPathDaemonLifecycle
import KeyPathWizardCore

/// Snapshot of KanataManager state for UI updates
struct KanataUIState {
    // Core Status
    // Removed: isRunning
    let lastError: String?
    let keyMappings: [KeyMapping]
    let ruleCollections: [RuleCollection]
    let customRules: [CustomRule]
    let currentLayerName: String
    let diagnostics: [KanataDiagnostic]
    let lastProcessExitCode: Int32?
    let lastConfigUpdate: Date

    // UI State (Legacy status removed)
    // Removed: errorReason, showWizard, launchFailureStatus

    // Validation & Save Status
    let showingValidationAlert: Bool
    let validationAlertTitle: String
    let validationAlertMessage: String
    let validationAlertActions: [ValidationAlertAction]
    let saveStatus: SaveStatus
}
