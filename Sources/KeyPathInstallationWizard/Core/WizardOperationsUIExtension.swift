import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore

// MARK: - UI-Layer WizardOperations Extension

// This extends WizardOperations (from Core) with UI-specific factory methods that need UI types

extension WizardOperations {
    /// State detection operation (UI-layer only - uses WizardStateMachine)
    public static func stateDetection(
        stateMachine: WizardStateMachine?,
        freshness: WizardSystemSnapshotFreshness = .fresh,
        progressCallback: @escaping @Sendable (Double) -> Void = { _ in }
    ) -> AsyncOperation<SystemStateResult> {
        AsyncOperation<SystemStateResult>(
            id: "state_detection",
            name: "System State Detection"
        ) { operationProgressCallback in
            if let machine = stateMachine {
                progressCallback(0.1)
                let result = await machine.detectCurrentState(freshness: freshness)
                try Task.checkCancellation()
                progressCallback(1.0)
                operationProgressCallback(1.0)
                return result
            } else {
                progressCallback(1.0)
                operationProgressCallback(1.0)
                return timeoutResult()
            }
        }
    }

    private static func timeoutResult() -> SystemStateResult {
        let issue = WizardIssue(
            identifier: .validationTimeout,
            severity: .warning,
            category: .daemon,
            title: String(localized: "System check timed out"),
            description: String(localized: "KeyPath couldn't finish checking system status. This can happen if the helper or services are unresponsive."),
            autoFixAction: nil,
            userAction: String(localized: "Try restarting KeyPath.")
        )
        return SystemStateResult(
            state: .serviceNotRunning,
            issues: [issue],
            autoFixActions: [],
            detectionTimestamp: Date(),
            captureStatus: .timedOut
        )
    }
}
