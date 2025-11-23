import Foundation
import KeyPathDaemonLifecycle
import KeyPathWizardCore

/// Snapshot of KanataManager state for UI updates
struct KanataUIState: Sendable {
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
    let validationError: ConfigValidationError?
    let saveStatus: SaveStatus
}

/// Error state for configuration validation to be handled by UI
enum ConfigValidationError: Equatable, Sendable {
    case invalidStartup(errors: [String], backupPath: String)
    case saveFailed(title: String, errors: [String])
}
