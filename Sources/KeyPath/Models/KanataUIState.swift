import Foundation
import KeyPathDaemonLifecycle
import KeyPathWizardCore

/// Snapshot of KanataManager state for UI updates
struct KanataUIState {
    let isRunning: Bool
    let lastError: String?
    let keyMappings: [KeyMapping]
    let diagnostics: [KanataDiagnostic]
    let lastProcessExitCode: Int32?
    let lastConfigUpdate: Date
    let currentState: SimpleKanataState
    let errorReason: String?
    let showWizard: Bool
    let launchFailureStatus: LaunchFailureStatus?
    let autoStartAttempts: Int
    let lastHealthCheck: Date?
    let retryCount: Int
    let isRetryingAfterFix: Bool
    let lifecycleState: LifecycleStateMachine.KanataState
    let lifecycleErrorMessage: String?
    let isBusy: Bool
    let canPerformActions: Bool
    let autoStartAttempted: Bool
    let autoStartSucceeded: Bool
    let autoStartFailureReason: String?
    let shouldShowWizard: Bool
    let showingValidationAlert: Bool
    let validationAlertTitle: String
    let validationAlertMessage: String
    let validationAlertActions: [ValidationAlertAction]
    let saveStatus: SaveStatus
}
