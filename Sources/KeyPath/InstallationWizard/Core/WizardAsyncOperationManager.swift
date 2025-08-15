import Foundation
import SwiftUI

/// Manages async operations throughout the wizard with consistent patterns and error handling
@MainActor
class WizardAsyncOperationManager: ObservableObject {
    // MARK: - Published State

    @Published var runningOperations: Set<String> = []
    @Published var lastError: WizardError?
    @Published var operationProgress: [String: Double] = [:]

    // MARK: - Operation Management

    /// Execute an async operation with consistent error handling and loading state
    func execute<T>(
        operation: AsyncOperation<T>,
        onSuccess: @escaping (T) -> Void = { _ in },
        onFailure: @escaping (WizardError) -> Void = { _ in }
    ) async {
        let operationId = operation.id

        // Start operation
        runningOperations.insert(operationId)
        lastError = nil

        AppLogger.shared.log("🔄 [AsyncOp] Starting operation: \(operation.name)")

        do {
            let result = try await operation.execute { progress in
                Task { @MainActor in
                    self.operationProgress[operationId] = progress
                }
            }

            AppLogger.shared.log("✅ [AsyncOp] Operation completed: \(operation.name)")
            onSuccess(result)

        } catch {
            let wizardError = WizardError.fromError(error, operation: operation.name)
            AppLogger.shared.log(
                "❌ [AsyncOp] Operation failed: \(operation.name) - \(wizardError.localizedDescription)")

            lastError = wizardError
            onFailure(wizardError)
        }

        // Clean up
        runningOperations.remove(operationId)
        operationProgress.removeValue(forKey: operationId)
    }

    /// Check if a specific operation is running
    func isRunning(_ operationId: String) -> Bool {
        runningOperations.contains(operationId)
    }

    /// Get progress for a specific operation
    func getProgress(_ operationId: String) -> Double {
        operationProgress[operationId] ?? 0.0
    }

    /// Cancel all running operations
    func cancelAllOperations() {
        runningOperations.removeAll()
        operationProgress.removeAll()
        AppLogger.shared.log("🛑 [AsyncOp] All operations cancelled")
    }

    /// Reset stuck operations (useful when operations don't clean up properly)
    func resetStuckOperations() {
        AppLogger.shared.log(
            "🔧 [AsyncOp] Resetting \(runningOperations.count) stuck operations: \(runningOperations)")
        runningOperations.removeAll()
        operationProgress.removeAll()
    }

    /// Check if any operations are running
    var hasRunningOperations: Bool {
        !runningOperations.isEmpty
    }
}

// MARK: - Async Operation Definition

/// Represents an async operation that can be executed by the manager
struct AsyncOperation<T> {
    let id: String
    let name: String
    let execute: (@escaping @Sendable (Double) -> Void) async throws -> T

    init(
        id: String, name: String,
        execute: @escaping (@escaping @Sendable (Double) -> Void) async throws -> T
    ) {
        self.id = id
        self.name = name
        self.execute = execute
    }
}

// MARK: - Common Operations

// MARK: - Operation Factory

enum WizardOperations {
    /// State detection operation
    static func stateDetection(stateManager: WizardStateManager) -> AsyncOperation<SystemStateResult> {
        AsyncOperation<SystemStateResult>(
            id: "state_detection",
            name: "System State Detection"
        ) { progressCallback in
            progressCallback(0.1)
            let result = await stateManager.detectCurrentState()
            progressCallback(1.0)
            return result
        }
    }

    /// Auto-fix operation with detailed progress tracking
    static func autoFix(
        action: AutoFixAction,
        autoFixer: WizardAutoFixerManager
    ) -> AsyncOperation<Bool> {
        AsyncOperation<Bool>(
            id: "auto_fix_\(String(describing: action))",
            name: "Auto Fix: \(action.displayName)"
        ) { progressCallback in
            // Start progress
            progressCallback(0.1)

            // Provide more granular progress based on action type
            switch action {
            case .terminateConflictingProcesses:
                progressCallback(0.2)
                let success = await autoFixer.performAutoFix(action)
                progressCallback(0.8)

                // Brief pause to show completion
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                progressCallback(1.0)
                return success

            case .installMissingComponents, .installViaBrew:
                // Longer operations - more detailed progress
                progressCallback(0.15)

                // Simulate preparation phase
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                progressCallback(0.25)

                let success = await autoFixer.performAutoFix(action)
                progressCallback(0.85)

                // Brief pause for verification
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                progressCallback(1.0)
                return success

            case .activateVHIDDeviceManager:
                // Driver activation can take time
                progressCallback(0.2)
                let success = await autoFixer.performAutoFix(action)
                progressCallback(0.9)

                // Allow time for driver activation to complete
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                progressCallback(1.0)
                return success

            default:
                // Standard operations
                progressCallback(0.25)
                let success = await autoFixer.performAutoFix(action)
                progressCallback(0.9)

                // Brief completion pause
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                progressCallback(1.0)
                return success
            }
        }
    }

    /// Service start operation
    static func startService(kanataManager: KanataManager) -> AsyncOperation<Bool> {
        AsyncOperation<Bool>(
            id: "start_service",
            name: "Start Kanata Service"
        ) { progressCallback in
            progressCallback(0.1)
            await kanataManager.startKanataWithSafetyTimeout()
            progressCallback(0.8)

            // Wait for service to fully start
            try await Task.sleep(nanoseconds: 1_000_000_000)
            progressCallback(1.0)

            return kanataManager.isRunning
        }
    }

    /// Permission grant operation (opens settings and waits for user)
    static func grantPermission(
        type: PermissionType,
        kanataManager: KanataManager
    ) -> AsyncOperation<Bool> {
        AsyncOperation<Bool>(
            id: "grant_permission_\(type.rawValue)",
            name: "Grant Permission: \(type.displayName)"
        ) { progressCallback in
            progressCallback(0.1)

            // Open settings
            switch type {
            case .inputMonitoring:
                kanataManager.openInputMonitoringSettings()
            case .accessibility:
                kanataManager.openAccessibilitySettings()
            }

            progressCallback(0.3)

            // Wait and periodically check for permission grant
            var attempts = 0
            let maxAttempts = 30 // 30 seconds max

            while attempts < maxAttempts {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                attempts += 1
                progressCallback(0.3 + (Double(attempts) / Double(maxAttempts)) * 0.7)

                let hasPermission =
                    switch type {
                    case .inputMonitoring:
                        false // Always return false to prevent auto-addition to Input Monitoring
                    case .accessibility:
                        PermissionService.shared.hasAccessibilityPermission()
                    }

                if hasPermission {
                    progressCallback(1.0)
                    return true
                }
            }

            // Timeout
            return false
        }
    }
}

// MARK: - Permission Type

enum PermissionType: String {
    case inputMonitoring
    case accessibility

    var displayName: String {
        switch self {
        case .inputMonitoring: "Input Monitoring"
        case .accessibility: "Accessibility"
        }
    }
}

// MARK: - Error Handling

struct WizardError: LocalizedError {
    let operation: String
    let underlying: Error?
    let userMessage: String
    let recoveryActions: [String]

    var errorDescription: String? {
        userMessage
    }

    var recoverySuggestion: String? {
        if recoveryActions.isEmpty {
            return nil
        }

        if recoveryActions.count == 1 {
            return "Try this: \(recoveryActions[0])"
        }

        let numberedActions = recoveryActions.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return "Try these steps:\n\n" + numberedActions.joined(separator: "\n")
    }

    static func fromError(_ error: Error, operation: String) -> WizardError {
        let (friendlyMessage, recoveryActions) = createUserFriendlyMessage(for: operation, error: error)

        return WizardError(
            operation: operation,
            underlying: error,
            userMessage: friendlyMessage,
            recoveryActions: recoveryActions
        )
    }

    static func timeout(operation: String) -> WizardError {
        let (friendlyMessage, recoveryActions) = createTimeoutMessage(for: operation)

        return WizardError(
            operation: operation,
            underlying: nil,
            userMessage: friendlyMessage,
            recoveryActions: recoveryActions
        )
    }

    static func cancelled(operation: String) -> WizardError {
        WizardError(
            operation: operation,
            underlying: nil,
            userMessage: "Setup was cancelled by the user.",
            recoveryActions: [
                "Click the 'Retry' button to try again",
                "Use manual setup if automatic setup continues to fail"
            ]
        )
    }

    // MARK: - User-Friendly Message Creation

    private static func createUserFriendlyMessage(for operation: String, error _: Error) -> (
        String, [String]
    ) {
        switch operation {
        case let op where op.contains("Auto Fix: Terminate Conflicting Processes"):
            (
                "Unable to stop conflicting keyboard apps",
                [
                    "Manually quit Karabiner-Elements from the menu bar",
                    "Check Activity Monitor for any remaining Karabiner processes",
                    "Restart your Mac if processes won't stop"
                ]
            )

        case let op where op.contains("Auto Fix: Install Missing Components"):
            (
                "Failed to install required keyboard remapping components",
                [
                    "Check your internet connection",
                    "Make sure you have administrator privileges",
                    "Use KeyPath's Installation Wizard to install Kanata automatically"
                ]
            )

        case let op where op.contains("Auto Fix: Start Kanata Service"):
            (
                "The keyboard remapping service won't start",
                [
                    "Grant necessary permissions in System Preferences",
                    "Check that no conflicting keyboard apps are running",
                    "Try restarting your Mac"
                ]
            )

        case let op where op.contains("Auto Fix: Activating Driver Extensions"):
            (
                "Driver extensions need manual approval for security",
                [
                    "Open System Preferences → Privacy & Security → Driver Extensions",
                    "Find 'Karabiner-VirtualHIDDevice-Manager.app' and enable it",
                    "You may need to restart your Mac after enabling"
                ]
            )

        case let op where op.contains("System State Detection"):
            (
                "Unable to check your system's current setup",
                [
                    "Check that KeyPath has the necessary permissions",
                    "Try closing and reopening KeyPath",
                    "Make sure no other setup processes are running"
                ]
            )

        case let op where op.contains("Grant Permission"):
            (
                "KeyPath needs additional system permissions to work properly",
                [
                    "Open System Preferences → Privacy & Security",
                    "Find 'Input Monitoring' and 'Accessibility' sections",
                    "Make sure KeyPath and Kanata are both enabled"
                ]
            )

        default:
            // Generic fallback with more helpful language
            (
                "Something went wrong during setup",
                [
                    "Try the operation again",
                    "Check that you have administrator privileges",
                    "Make sure no antivirus software is blocking KeyPath"
                ]
            )
        }
    }

    private static func createTimeoutMessage(for operation: String) -> (String, [String]) {
        switch operation {
        case let op where op.contains("Permission"):
            (
                "The permission setup is taking longer than expected",
                [
                    "Open System Preferences manually and grant the required permissions",
                    "Make sure to enable permissions for both KeyPath and Kanata",
                    "Close and reopen KeyPath after granting permissions"
                ]
            )

        case let op where op.contains("Service"):
            (
                "The keyboard service is taking too long to start",
                [
                    "Check Activity Monitor for any hung processes",
                    "Make sure all required permissions are granted",
                    "Try restarting your Mac if the problem persists"
                ]
            )

        default:
            (
                "The operation took longer than expected",
                [
                    "Try the operation again",
                    "Check that your system isn't overloaded",
                    "Consider restarting KeyPath if problems persist"
                ]
            )
        }
    }
}

// MARK: - Auto Fix Action Extension

extension AutoFixAction {
    var displayName: String {
        switch self {
        case .terminateConflictingProcesses:
            "Terminate Conflicting Processes"
        case .startKarabinerDaemon:
            "Start Karabiner Daemon"
        case .restartVirtualHIDDaemon:
            "Restart Virtual HID Daemon"
        case .installMissingComponents:
            "Install Missing Components"
        case .createConfigDirectories:
            "Create Config Directories"
        case .activateVHIDDeviceManager:
            "Activate VirtualHIDDevice Manager"
        case .installLaunchDaemonServices:
            "Install LaunchDaemon Services"
        case .adoptOrphanedProcess:
            "Adopt Orphaned Process"
        case .replaceOrphanedProcess:
            "Replace Orphaned Process"
        case .installViaBrew:
            "Install via Homebrew"
        case .repairVHIDDaemonServices:
            "Repair VHID Daemon Services"
        case .synchronizeConfigPaths:
            "Synchronize Config Paths"
        case .restartUnhealthyServices:
            "Restart Unhealthy Services"
        }
    }
}
