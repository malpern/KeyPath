import Foundation
import KeyPathDaemonLifecycle
import KeyPathWizardCore

/// Snapshot of RuntimeCoordinator state for UI updates
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

    /// Empty state for initialization fallback
    static let empty = KanataUIState(
        lastError: nil,
        keyMappings: [],
        ruleCollections: [],
        customRules: [],
        currentLayerName: "base",
        diagnostics: [],
        lastProcessExitCode: nil,
        lastConfigUpdate: Date(),
        validationError: nil,
        saveStatus: .idle
    )
}

/// Error state for configuration validation to be handled by UI
enum ConfigValidationError: Equatable, Sendable {
    case invalidStartup(errors: [String], backupPath: String)
    case saveFailed(title: String, errors: [String])
}
