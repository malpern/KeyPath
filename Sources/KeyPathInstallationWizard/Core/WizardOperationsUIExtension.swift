import Foundation
import KeyPathCore
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
            // Forward progress from SystemValidator to the operation callback
            if let machine = stateMachine {
                progressCallback(0.1)
                await machine.refresh(freshness: freshness)

                progressCallback(1.0)
                operationProgressCallback(1.0)
                // machine.refresh() completed — read state it stored
                return await MainActor.run {
                    let issues = machine.wizardIssues
                    let captured = machine.lastWizardSnapshot
                    if !issues.isEmpty || machine.wizardState == .active {
                        return SystemStateResult(
                            state: machine.wizardState,
                            issues: issues,
                            autoFixActions: [],
                            detectionTimestamp: Date(),
                            captureStatus: captured?.captureStatus ?? .complete,
                            helperInstalled: captured?.helperInstalled ?? false,
                            helperNeedsApproval: captured?.helperNeedsApproval ?? false
                        )
                    }
                    return timeoutResult()
                }
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
            title: "System check timed out",
            description: "KeyPath couldn't finish checking system status. This can happen if the helper or services are unresponsive.",
            autoFixAction: nil,
            userAction: "Try restarting KeyPath."
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

// MARK: - Timeout helper for auto-fix actions

public struct AutoFixTimeoutError: Error {}

public func runWithTimeout<T: Sendable>(
    seconds: Double,
    operation: @Sendable @escaping () async -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            let clock = ContinuousClock()
            try await clock.sleep(for: .seconds(seconds))
            throw AutoFixTimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
