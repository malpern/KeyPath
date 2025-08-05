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
    return runningOperations.contains(operationId)
  }

  /// Get progress for a specific operation
  func getProgress(_ operationId: String) -> Double {
    return operationProgress[operationId] ?? 0.0
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
    return !runningOperations.isEmpty
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

  /// Auto-fix operation
  static func autoFix(
    action: AutoFixAction,
    autoFixer: WizardAutoFixerManager
  ) -> AsyncOperation<Bool> {
    AsyncOperation<Bool>(
      id: "auto_fix_\(String(describing: action))",
      name: "Auto Fix: \(action.displayName)"
    ) { progressCallback in
      progressCallback(0.2)
      let success = await autoFixer.performAutoFix(action)
      progressCallback(1.0)
      return success
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
      let maxAttempts = 30  // 30 seconds max

      while attempts < maxAttempts {
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        attempts += 1
        progressCallback(0.3 + (Double(attempts) / Double(maxAttempts)) * 0.7)

        let hasPermission =
          switch type {
          case .inputMonitoring:
            kanataManager.hasInputMonitoringPermission()
          case .accessibility:
            kanataManager.hasAccessibilityPermission()
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
    case .inputMonitoring: return "Input Monitoring"
    case .accessibility: return "Accessibility"
    }
  }
}

// MARK: - Error Handling

struct WizardError: LocalizedError {
  let operation: String
  let underlying: Error?
  let userMessage: String

  var errorDescription: String? {
    return userMessage
  }

  static func fromError(_ error: Error, operation: String) -> WizardError {
    return WizardError(
      operation: operation,
      underlying: error,
      userMessage: "Failed to \(operation.lowercased()): \(error.localizedDescription)"
    )
  }

  static func timeout(operation: String) -> WizardError {
    return WizardError(
      operation: operation,
      underlying: nil,
      userMessage: "Operation timed out: \(operation)"
    )
  }

  static func cancelled(operation: String) -> WizardError {
    return WizardError(
      operation: operation,
      underlying: nil,
      userMessage: "Operation was cancelled: \(operation)"
    )
  }
}

// MARK: - Auto Fix Action Extension

extension AutoFixAction {
  var displayName: String {
    switch self {
    case .terminateConflictingProcesses:
      return "Terminate Conflicting Processes"
    case .startKarabinerDaemon:
      return "Start Karabiner Daemon"
    case .restartVirtualHIDDaemon:
      return "Restart Virtual HID Daemon"
    case .installMissingComponents:
      return "Install Missing Components"
    case .createConfigDirectories:
      return "Create Config Directories"
    case .activateVHIDDeviceManager:
      return "Activate VirtualHIDDevice Manager"
    case .installLaunchDaemonServices:
      return "Install LaunchDaemon Services"
    case .installViaBrew:
      return "Install via Homebrew"
    }
  }
}
