import Foundation
import KeyPathCore
import KeyPathWizardCore

// MARK: - UI-Layer WizardOperations Extension

// This extends WizardOperations (from Core) with UI-specific factory methods that need UI types

extension WizardOperations {
    /// State detection operation (UI-layer only - uses WizardStateMachine)
    static func stateDetection(
        stateMachine: WizardStateMachine?,
        progressCallback: @escaping @Sendable (Double) -> Void = { _ in }
    ) -> AsyncOperation<SystemStateResult> {
        enum StateDetectionError: Error {
            case timeout
        }

        return AsyncOperation<SystemStateResult>(
            id: "state_detection",
            name: "System State Detection"
        ) { operationProgressCallback in
            // Forward progress from SystemValidator to the operation callback
            if let machine = stateMachine {
                progressCallback(0.1)
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { await machine.refresh() }
                        group.addTask {
                            try await Task.sleep(nanoseconds: 12_000_000_000)
                            throw StateDetectionError.timeout
                        }
                        _ = try await group.next()
                        group.cancelAll()
                    }
                } catch {
                    AppLogger.shared.log("⚠️ [Wizard] State detection timed out: \(error)")
                    progressCallback(1.0)
                    operationProgressCallback(1.0)
                    return timeoutResult()
                }

                progressCallback(1.0)
                operationProgressCallback(1.0)
                // Adapt snapshot on the main actor
                return await MainActor.run {
                    if let snapshot = machine.systemSnapshot {
                        let context = SystemContext(
                            permissions: snapshot.permissions,
                            services: snapshot.health,
                            conflicts: snapshot.conflicts,
                            components: snapshot.components,
                            helper: snapshot.helper,
                            system: EngineSystemInfo(macOSVersion: "unknown", driverCompatible: true),
                            timestamp: snapshot.timestamp
                        )
                        return SystemContextAdapter.adapt(context)
                    } else {
                        return timeoutResult()
                    }
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
            identifier: .daemon,
            severity: .warning,
            category: .daemon,
            title: "System check timed out",
            description: "KeyPath couldn't finish checking system status. This can happen if the helper or services are unresponsive.",
            autoFixAction: .restartUnhealthyServices,
            userAction: "Try restarting KeyPath or click Restart Services."
        )
        return SystemStateResult(
            state: .serviceNotRunning,
            issues: [issue],
            autoFixActions: [.restartUnhealthyServices],
            detectionTimestamp: Date()
        )
    }
}

// MARK: - Timeout helper for auto-fix actions

struct AutoFixTimeoutError: Error {}

func runWithTimeout<T: Sendable>(
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
