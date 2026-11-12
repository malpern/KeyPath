import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import Observation
import SwiftUI

/// Manages async operations throughout the wizard with consistent patterns and error handling
/// Operations run in background threads to keep UI responsive
@Observable
@MainActor
public class WizardAsyncOperationManager {
    public init() {}

    // MARK: - Observable State (MainActor for UI updates)

    public var runningOperations: Set<String> = []
    public var lastError: WizardError?
    public var operationProgress: [String: Double] = [:]

    // MARK: - Cancellation Support

    private var runningTasks: [String: Task<Void, Never>] = [:]
    private var operationGenerations: [String: UUID] = [:]

    /// Default timeout for operations (30 seconds)
    private let defaultTimeout: TimeInterval = 30.0

    // MARK: - Operation Management

    /// Execute an async operation in the background with consistent error handling and loading state
    /// This method returns immediately and executes the operation in a background task
    /// - Parameters:
    ///   - operation: The async operation to execute
    ///   - timeout: Optional timeout in seconds (default: 30s)
    ///   - onSuccess: Success handler called on main actor
    ///   - onFailure: Failure handler called on main actor
    public func execute<T: Sendable>(
        operation: AsyncOperation<T>,
        timeout: TimeInterval? = nil,
        onSuccess: @escaping @MainActor (T) async -> Void = { _ in },
        onFailure: @escaping @MainActor (WizardError) -> Void = { _ in }
    ) {
        let operationId = operation.id
        let timeoutDuration = timeout ?? defaultTimeout
        let generation = UUID()

        // Handle duplicate operation IDs: cancel existing operation if running
        if let existingTask = runningTasks[operationId] {
            AppLogger.shared.warn("🔄 [AsyncOp] Cancelling duplicate operation: \(operation.name)")
            existingTask.cancel()
            runningTasks.removeValue(forKey: operationId)
            runningOperations.remove(operationId)
            operationProgress.removeValue(forKey: operationId)
        }
        operationGenerations[operationId] = generation
        runningOperations.insert(operationId)
        lastError = nil

        // Create a background task that doesn't block the UI
        let task = Task { [weak self] in
            guard let self else { return }

            let opName = operation.name
            AppLogger.shared.debug(
                "🔄 [AsyncOp] Starting background operation: \(opName) (timeout: \(timeoutDuration)s)"
            )

            do {
                // A task group waits for every child on exit, even after its
                // timer wins. A stream lets the deadline retire UI ownership
                // while a non-cooperative dependency finishes in the background.
                let (stream, continuation) = AsyncThrowingStream<T, Error>.makeStream()
                let operationTask = Task { @MainActor in
                    do {
                        let value = try await operation.execute { progress in
                            Task { @MainActor in
                                guard self.operationGenerations[operationId] == generation else { return }
                                self.operationProgress[operationId] = progress
                            }
                        }
                        continuation.yield(value)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                let deadlineTask = Task {
                    do {
                        try await ContinuousClock().sleep(for: .seconds(timeoutDuration))
                        continuation.finish(throwing: TimeoutError(operation: opName, timeout: timeoutDuration))
                    } catch {}
                }
                continuation.onTermination = { _ in
                    operationTask.cancel()
                    deadlineTask.cancel()
                }
                defer {
                    operationTask.cancel()
                    deadlineTask.cancel()
                    continuation.finish()
                }
                var iterator = stream.makeAsyncIterator()
                guard let result = try await iterator.next() else { throw CancellationError() }

                // Check if task was cancelled
                guard !Task.isCancelled else {
                    AppLogger.shared.debug("🛑 [AsyncOp] Operation cancelled: \(opName)")
                    cleanupOperation(operationId, generation: generation)
                    return
                }
                guard operationGenerations[operationId] == generation else { return }

                AppLogger.shared.debug("✅ [AsyncOp] Operation completed: \(opName)")

                // Follow-up UI work can suspend or start another operation. The
                // completed check must not keep its spinner or block refreshes.
                cleanupOperation(operationId, generation: generation)
                await onSuccess(result)

            } catch {
                // Check if this was a cancellation
                if Task.isCancelled {
                    AppLogger.shared.debug("🛑 [AsyncOp] Operation cancelled: \(opName)")
                } else {
                    guard operationGenerations[operationId] == generation else { return }
                    let wizardError: WizardError
                    if let timeoutError = error as? TimeoutError {
                        wizardError = WizardError.timeout(operation: timeoutError.operation)
                        AppLogger.shared.warn(
                            "⏱️ [AsyncOp] Operation timed out: \(opName) after \(timeoutDuration)s"
                        )
                    } else {
                        wizardError = WizardError.fromError(error, operation: opName)
                        AppLogger.shared.error(
                            "❌ [AsyncOp] Operation failed: \(opName) - \(wizardError.localizedDescription)"
                        )
                    }

                    // Update error state and call failure handler on main thread
                    await MainActor.run {
                        guard self.operationGenerations[operationId] == generation else { return }
                        self.cleanupOperation(operationId, generation: generation)
                        self.lastError = wizardError
                        onFailure(wizardError)
                    }
                }
            }

            // Clean up
            cleanupOperation(operationId, generation: generation)
        }

        // Store the task reference for cancellation
        runningTasks[operationId] = task
    }

    /// Check if a specific operation is running
    @MainActor public func isRunning(_ operationId: String) -> Bool {
        runningOperations.contains(operationId)
    }

    /// Get progress for a specific operation
    @MainActor public func getProgress(_ operationId: String) -> Double {
        operationProgress[operationId] ?? 0.0
    }

    /// Cancel all running operations (legacy method, may block main thread)
    public func cancelAllOperations() {
        let tasksToCancel = runningTasks.values

        // Cancel all tasks
        for task in tasksToCancel {
            task.cancel()
        }

        runningTasks.removeAll()
        operationGenerations.removeAll()
        runningOperations.removeAll()
        operationProgress.removeAll()

        AppLogger.shared.debug("🛑 [AsyncOp] All operations cancelled")
    }

    /// Cancel all running operations asynchronously (guaranteed no main thread blocking)
    public func cancelAllOperationsAsync() {
        // Perform all cancellation work in background without any main thread involvement
        let tasksToCancel = Array(runningTasks.values)
        runningTasks.removeAll()

        // Cancel all tasks (this doesn't block)
        for task in tasksToCancel {
            task.cancel()
        }

        AppLogger.shared.debug(
            "🛑 [AsyncOp] All operations cancelled asynchronously (\(tasksToCancel.count) tasks)"
        )

        // Retire ownership immediately so cancelled work cannot affect a successor.
        operationGenerations.removeAll()
        runningOperations.removeAll()
        operationProgress.removeAll()
    }

    /// Cancel a specific operation
    public func cancelOperation(_ operationId: String) {
        let task = runningTasks[operationId]

        task?.cancel()

        AppLogger.shared.debug("🛑 [AsyncOp] Operation cancelled: \(operationId)")
    }

    /// Clean up after operation completion or cancellation
    @MainActor
    private func cleanupOperation(_ operationId: String, generation: UUID) {
        guard operationGenerations[operationId] == generation else { return }
        operationGenerations.removeValue(forKey: operationId)
        runningOperations.remove(operationId)
        operationProgress.removeValue(forKey: operationId)

        runningTasks.removeValue(forKey: operationId)
    }

    /// Reset stuck operations (useful when operations don't clean up properly)
    @MainActor public func resetStuckOperations() {
        AppLogger.shared.warn(
            "🔧 [AsyncOp] Resetting \(runningOperations.count) stuck operations: \(runningOperations)"
        )
        runningOperations.removeAll()
        operationProgress.removeAll()
    }

    /// Check if any operations are running
    @MainActor public var hasRunningOperations: Bool {
        !runningOperations.isEmpty
    }
}

// MARK: - Timeout Error

private struct TimeoutError: Error {
    let operation: String
    let timeout: TimeInterval

    var localizedDescription: String {
        "Operation '\(operation)' timed out after \(timeout) seconds"
    }
}

// MARK: - Async Operation Definition

/// Represents an async operation that can be executed by the manager
public struct AsyncOperation<T> {
    public let id: String
    public let name: String
    public let execute: (@escaping @Sendable (Double) -> Void) async throws -> T

    public init(
        id: String, name: String,
        execute: @escaping (@escaping @Sendable (Double) -> Void) async throws -> T
    ) {
        self.id = id
        self.name = name
        self.execute = execute
    }
}

// MARK: - Operation Factory

public enum WizardOperations {
    /// Service start operation
    public static func startService(kanataManager: any RuntimeCoordinating) -> AsyncOperation<Bool> {
        AsyncOperation<Bool>(
            id: "start_service",
            name: "Start KeyPath Runtime"
        ) { progressCallback in
            progressCallback(0.1)

            let restarted = await kanataManager.startKanata(
                reason: "Wizard async start operation"
            )

            progressCallback(restarted ? 0.85 : 0.6)

            if restarted {
                // Give the service a short window to settle so the summary screen doesn’t flicker.
                let clock = ContinuousClock()
                try await clock.sleep(for: .seconds(1))
            }

            progressCallback(1.0)

            return restarted
        }
    }
}

// MARK: - Error Handling

public struct WizardError: LocalizedError {
    public let operation: String
    public let underlying: Error?
    public let userMessage: String
    public let recoveryActions: [String]

    public var errorDescription: String? {
        userMessage
    }

    public var recoverySuggestion: String? {
        if recoveryActions.isEmpty {
            return nil
        }

        if recoveryActions.count == 1 {
            return String(localized: "Try this: \(recoveryActions[0])")
        }

        let numberedActions = recoveryActions.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return String(localized: "Try these steps:") + "\n\n" + numberedActions.joined(separator: "\n")
    }

    public static func fromError(_ error: Error, operation: String) -> WizardError {
        let (friendlyMessage, recoveryActions) = createUserFriendlyMessage(for: operation, error: error)

        return WizardError(
            operation: operation,
            underlying: error,
            userMessage: friendlyMessage,
            recoveryActions: recoveryActions
        )
    }

    public static func timeout(operation: String) -> WizardError {
        let (friendlyMessage, recoveryActions) = createTimeoutMessage(for: operation)

        return WizardError(
            operation: operation,
            underlying: nil,
            userMessage: friendlyMessage,
            recoveryActions: recoveryActions
        )
    }

    public static func cancelled(operation: String) -> WizardError {
        WizardError(
            operation: operation,
            underlying: nil,
            userMessage: String(localized: "Setup was cancelled by the user."),
            recoveryActions: [
                String(localized: "Click the 'Retry' button to try again"),
                String(localized: "Use manual setup if automatic setup continues to fail")
            ]
        )
    }

    // MARK: - User-Friendly Message Creation

    private static func createUserFriendlyMessage(for operation: String, error _: Error) -> (
        String, [String]
    ) {
        switch operation {
        case let op where op.contains("Auto Fix: Terminate Conflicting Processes"):
            return (
                String(localized: "Unable to stop conflicting keyboard apps"),
                [
                    String(localized: "Manually quit Karabiner-Elements from the menu bar"),
                    String(localized: "Check Activity Monitor for any remaining Karabiner processes"),
                    String(localized: "Restart your Mac if processes won't stop")
                ]
            )

        case let op where op.contains("Auto Fix: Start KeyPath Runtime"):
            return (
                String(localized: "The keyboard remapping service won't start"),
                [
                    String(localized: "Grant necessary permissions in System Settings"),
                    String(localized: "Check that no conflicting keyboard apps are running"),
                    String(localized: "Try restarting your Mac")
                ]
            )

        case let op where op.contains("System State Detection"):
            return (
                String(localized: "Unable to check your system's current setup"),
                [
                    String(localized: "Check that KeyPath has the necessary permissions"),
                    String(localized: "Try closing and reopening KeyPath"),
                    String(localized: "Make sure no other setup processes are running")
                ]
            )

        case let op where op.contains("Grant Permission"):
            return (
                String(localized: "KeyPath needs additional system permissions to work properly"),
                [
                    String(localized: "Open System Settings → Privacy & Security"),
                    String(localized: "Find the '\(AccessibilityPermissionPresentation.current.name)' section"),
                    String(localized: "Make sure KeyPath is enabled, then quit and reopen KeyPath")
                ]
            )

        default:
            // Extract action name for more helpful message
            let actionName = operation
                .replacingOccurrences(of: "Auto Fix: ", with: "")
                .replacingOccurrences(of: "auto_fix_", with: "")
            let message = actionName.isEmpty
                ? String(localized: "Couldn't complete setup step")
                : String(localized: "Couldn't complete \(actionName.lowercased())")
            return (
                message,
                [
                    String(localized: "Try the operation again"),
                    String(localized: "Check that you have administrator privileges"),
                    String(localized: "Restart KeyPath if the problem persists")
                ]
            )
        }
    }

    private static func createTimeoutMessage(for operation: String) -> (String, [String]) {
        switch operation {
        case let op where op.contains("Permission"):
            return (
                String(localized: "Waiting for permission grant timed out"),
                [
                    String(localized: "Open System Settings manually and grant the required permissions"),
                    String(localized: "Make sure to enable permissions for both KeyPath and Kanata"),
                    String(localized: "Close and reopen KeyPath after granting permissions")
                ]
            )

        case let op where op.contains("Start KeyPath Runtime"):
            return (
                String(localized: "Couldn't start the keyboard service"),
                [
                    String(localized: "Check that all required permissions are granted"),
                    String(localized: "Look for error messages in the wizard"),
                    String(localized: "Try restarting your Mac if the problem persists")
                ]
            )

        case let op where op.contains("Install"):
            return (
                String(localized: "Installation is taking longer than expected"),
                [
                    String(localized: "Check your internet connection"),
                    String(localized: "Try the operation again"),
                    String(localized: "Restart KeyPath if the problem persists")
                ]
            )

        case let op where op.contains("Terminate"):
            return (
                String(localized: "Couldn't stop conflicting apps"),
                [
                    String(localized: "Manually quit Karabiner-Elements from the menu bar"),
                    String(localized: "Check Activity Monitor for remaining processes"),
                    String(localized: "Try again after quitting the apps manually")
                ]
            )

        default:
            // Extract action name from "Auto Fix: ActionName" format
            let actionName = operation
                .replacingOccurrences(of: "Auto Fix: ", with: "")
                .replacingOccurrences(of: "auto_fix_", with: "")
            let message = actionName.isEmpty
                ? String(localized: "The operation timed out")
                : String(localized: "The \(actionName.lowercased()) timed out")
            return (
                message,
                [
                    String(localized: "Try the operation again"),
                    String(localized: "Check that your system isn't overloaded"),
                    String(localized: "Restart KeyPath if the problem persists")
                ]
            )
        }
    }
}

// MARK: - Auto Fix Action Extension

public extension AutoFixAction {
    var displayName: String {
        switch self {
        case .startSessionRuntime:
            String(localized: "Start Remapping Engine")
        }
    }
}
