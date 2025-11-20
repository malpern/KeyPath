import Foundation

/// Consolidated error type for KeyPath application
///
/// This unified error hierarchy replaces 19 scattered error types across the codebase,
/// providing a single, consistent error handling pattern following Apple best practices.
///
/// ## Migration Guide
///
/// Old error types (all deprecated):
/// - `ConfigurationError`, `ConfigError`, `ConfigManagerError`, `ConfigBackupError` → `.configuration(...)`
/// - `ProcessLifecycleError`, `LifecycleError`, `LaunchAgentError` → `.process(...)`
/// - `PermissionError`, `OracleError`, `PrivilegedOperationError`, `KeychainError` → `.permission(...)`
/// - `EventProcessingError`, `TapError`, `OutputError` → `.system(...)`
/// - `UDPError` → `.communication(...)`
/// - `CoordinatorError`, `SystemDetectionError`, `LoggingError` → appropriate category
///
/// ## Design Rationale
///
/// Following Apple's Swift Error Handling Best Practices (WWDC 2020):
/// - Single error type per domain (KeyPath application)
/// - Nested enums for logical grouping
/// - Rich context via associated values
/// - User-facing error descriptions via `LocalizedError`
/// - Recoverable vs. non-recoverable classification
///
public enum KeyPathError: Error, LocalizedError {
  // MARK: - Configuration Errors

  case configuration(ConfigurationError)

  public enum ConfigurationError: Equatable, Sendable {
    case fileNotFound(path: String)
    case loadFailed(reason: String)
    case saveFailed(reason: String)
    case validationFailed(errors: [String])
    case invalidFormat(reason: String)
    case watchingFailed(reason: String)
    case backupFailed(reason: String)
    case backupRestoreFailed(reason: String)
    case backupListFailed(reason: String)
    case parseError(line: Int?, message: String)
    case backupNotFound
    case corruptedFormat(details: String)
    case repairFailed(reason: String)
  }

  // MARK: - Process/Lifecycle Errors

  case process(ProcessError)

  public enum ProcessError: Equatable, Sendable {
    case startFailed(reason: String)
    case stopFailed(underlyingError: String)
    case terminateFailed(underlyingError: String)
    case notRunning
    case alreadyRunning
    case launchAgentLoadFailed(reason: String)
    case launchAgentUnloadFailed(reason: String)
    case launchAgentNotFound
    case stateTransitionFailed(from: String, to: String)
    case noManager
  }

  // MARK: - Permission/Security Errors

  case permission(PermissionError)

  public enum PermissionError: Equatable, Sendable {
    case accessibilityNotGranted
    case inputMonitoringNotGranted
    case notificationAuthorizationFailed
    case oracleInitializationFailed
    case keychainSaveFailed(status: Int)
    case keychainLoadFailed(status: Int)
    case keychainDeleteFailed(status: Int)
    case privilegedOperationFailed(operation: String, reason: String)
  }

  // MARK: - System/Hardware Errors

  case system(SystemError)

  public enum SystemError: Equatable, Sendable {
    case eventTapCreationFailed
    case eventTapEnableFailed
    case eventProcessingFailed(reason: String)
    case outputSynthesisFailed(reason: String)
    case invalidKeyCode(Int64)
    case deviceNotFound
    case driverNotLoaded(driver: String)
  }

  // MARK: - Communication Errors

  case communication(CommunicationError)

  public enum CommunicationError: Equatable, Sendable {
    case timeout
    case noResponse
    case invalidPort
    case invalidResponse
    case notAuthenticated
    case payloadTooLarge(size: Int)
    case connectionFailed(reason: String)
    case serializationFailed
    case deserializationFailed
  }

  // MARK: - Coordination Errors

  case coordination(CoordinationError)

  public enum CoordinationError: Equatable, Sendable {
    case invalidState(expected: String, actual: String)
    case operationCancelled
    case recordingFailed(reason: String)
    case systemDetectionFailed(component: String, reason: String)
    case conflictDetected(service: String)
  }

  // MARK: - Logging Errors

  case logging(LoggingError)

  public enum LoggingError: Equatable, Sendable {
    case fileCreationFailed(path: String)
    case writeFailed(reason: String)
    case logRotationFailed(reason: String)
  }

  // MARK: - LocalizedError Conformance

  public var errorDescription: String? {
    switch self {
    case .configuration(let error):
      configurationErrorDescription(error)
    case .process(let error):
      processErrorDescription(error)
    case .permission(let error):
      permissionErrorDescription(error)
    case .system(let error):
      systemErrorDescription(error)
    case .communication(let error):
      communicationErrorDescription(error)
    case .coordination(let error):
      coordinationErrorDescription(error)
    case .logging(let error):
      loggingErrorDescription(error)
    }
  }

  public var failureReason: String? {
    switch self {
    case .configuration:
      "Configuration operation failed"
    case .process:
      "Process lifecycle operation failed"
    case .permission:
      "Permission or security check failed"
    case .system:
      "System-level operation failed"
    case .communication:
      "Communication with service failed"
    case .coordination:
      "Coordination or state management failed"
    case .logging:
      "Logging operation failed"
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .configuration(.fileNotFound):
      "Check that the configuration file exists and the path is correct"
    case .configuration(.validationFailed):
      "Review the configuration syntax and fix any validation errors"
    case .permission(.accessibilityNotGranted):
      "Grant Accessibility permission in System Settings > Privacy & Security"
    case .permission(.inputMonitoringNotGranted):
      "Grant Input Monitoring permission in System Settings > Privacy & Security"
    case .process(.notRunning):
      "Start the Kanata service before performing this operation"
    case .process(.launchAgentNotFound):
      "Run the installation wizard to install required components"
    case .communication(.timeout):
      "Check that the Kanata service is running and restart if necessary"
    case .communication(.notAuthenticated):
      "Restart the service to refresh authentication"
    case .system(.driverNotLoaded):
      "Run the installation wizard to install the Karabiner driver"
    default:
      nil
    }
  }

  // MARK: - Error Classification

  /// Returns true if this error can potentially be recovered from automatically
  public var isRecoverable: Bool {
    switch self {
    case .configuration(.fileNotFound),
      .configuration(.loadFailed),
      .process(.notRunning),
      .process(.stopFailed),
      .communication(.timeout),
      .communication(.noResponse):
      true
    case .permission,
      .system(.eventTapCreationFailed),
      .system(.driverNotLoaded):
      false
    default:
      false
    }
  }

  /// Returns true if this error should be shown to the user (vs. logged only)
  public var shouldDisplayToUser: Bool {
    switch self {
    case .permission,
      .configuration(.validationFailed),
      .process(.startFailed),
      .system(.driverNotLoaded):
      true
    case .logging,
      .coordination(.operationCancelled):
      false
    default:
      true
    }
  }

  // MARK: - Private Error Descriptions

  private func configurationErrorDescription(_ error: ConfigurationError) -> String {
    switch error {
    case .fileNotFound(let path):
      "Configuration file not found: \(path)"
    case .loadFailed(let reason):
      "Failed to load configuration: \(reason)"
    case .saveFailed(let reason):
      "Failed to save configuration: \(reason)"
    case .validationFailed(let errors):
      "Configuration validation failed: \(errors.joined(separator: ", "))"
    case .invalidFormat(let reason):
      "Invalid configuration format: \(reason)"
    case .watchingFailed(let reason):
      "Failed to watch configuration file: \(reason)"
    case .backupFailed(let reason):
      "Failed to create backup: \(reason)"
    case .backupRestoreFailed(let reason):
      "Failed to restore from backup: \(reason)"
    case .backupListFailed(let reason):
      "Failed to list backups: \(reason)"
    case .parseError(let line, let message):
      if let line {
        "Parse error at line \(line): \(message)"
      } else {
        "Parse error: \(message)"
      }
    case .backupNotFound:
      "No backup configuration found"
    case .corruptedFormat(let details):
      "Configuration file is corrupted: \(details)"
    case .repairFailed(let reason):
      "Failed to repair configuration: \(reason)"
    }
  }

  private func processErrorDescription(_ error: ProcessError) -> String {
    switch error {
    case .startFailed(let reason):
      "Process start failed: \(reason)"
    case .stopFailed(let underlyingError):
      "Process stop failed: \(underlyingError)"
    case .terminateFailed(let underlyingError):
      "Process termination failed: \(underlyingError)"
    case .notRunning:
      "Process is not running"
    case .alreadyRunning:
      "Process is already running"
    case .launchAgentLoadFailed(let reason):
      "Failed to load launch agent: \(reason)"
    case .launchAgentUnloadFailed(let reason):
      "Failed to unload launch agent: \(reason)"
    case .launchAgentNotFound:
      "Launch agent not found"
    case .stateTransitionFailed(let from, let to):
      "State transition failed from \(from) to \(to)"
    case .noManager:
      "No manager available"
    }
  }

  private func permissionErrorDescription(_ error: PermissionError) -> String {
    switch error {
    case .accessibilityNotGranted:
      "Accessibility permission not granted"
    case .inputMonitoringNotGranted:
      "Input Monitoring permission not granted"
    case .notificationAuthorizationFailed:
      "Notification authorization failed"
    case .oracleInitializationFailed:
      "Permission oracle initialization failed"
    case .keychainSaveFailed(let status):
      "Keychain save failed with status: \(status)"
    case .keychainLoadFailed(let status):
      "Keychain load failed with status: \(status)"
    case .keychainDeleteFailed(let status):
      "Keychain delete failed with status: \(status)"
    case .privilegedOperationFailed(let operation, let reason):
      "Privileged operation '\(operation)' failed: \(reason)"
    }
  }

  private func systemErrorDescription(_ error: SystemError) -> String {
    switch error {
    case .eventTapCreationFailed:
      "Failed to create event tap"
    case .eventTapEnableFailed:
      "Failed to enable event tap"
    case .eventProcessingFailed(let reason):
      "Event processing failed: \(reason)"
    case .outputSynthesisFailed(let reason):
      "Output synthesis failed: \(reason)"
    case .invalidKeyCode(let code):
      "Invalid key code: \(code)"
    case .deviceNotFound:
      "Device not found"
    case .driverNotLoaded(let driver):
      "Driver not loaded: \(driver)"
    }
  }

  private func communicationErrorDescription(_ error: CommunicationError) -> String {
    switch error {
    case .timeout:
      "Communication timeout"
    case .noResponse:
      "No response received from server"
    case .invalidPort:
      "Invalid port number"
    case .invalidResponse:
      "Invalid response from server"
    case .notAuthenticated:
      "Not authenticated"
    case .payloadTooLarge(let size):
      "Payload too large: \(size) bytes"
    case .connectionFailed(let reason):
      "Connection failed: \(reason)"
    case .serializationFailed:
      "Failed to serialize data"
    case .deserializationFailed:
      "Failed to deserialize response"
    }
  }

  private func coordinationErrorDescription(_ error: CoordinationError) -> String {
    switch error {
    case .invalidState(let expected, let actual):
      "Invalid state: expected \(expected), got \(actual)"
    case .operationCancelled:
      "Operation cancelled"
    case .recordingFailed(let reason):
      "Recording failed: \(reason)"
    case .systemDetectionFailed(let component, let reason):
      "System detection failed for \(component): \(reason)"
    case .conflictDetected(let service):
      "Conflict detected with \(service)"
    }
  }

  private func loggingErrorDescription(_ error: LoggingError) -> String {
    switch error {
    case .fileCreationFailed(let path):
      "Failed to create log file: \(path)"
    case .writeFailed(let reason):
      "Log write failed: \(reason)"
    case .logRotationFailed(let reason):
      "Log rotation failed: \(reason)"
    }
  }
}

// MARK: - Convenience Constructors

extension KeyPathError {
  /// Create a configuration file not found error
  public static func configFileNotFound(_ path: String) -> KeyPathError {
    .configuration(.fileNotFound(path: path))
  }

  /// Create a process start failed error
  public static func processStartFailed(_ reason: String) -> KeyPathError {
    .process(.startFailed(reason: reason))
  }

  /// Create an accessibility permission error
  public static var accessibilityNotGranted: KeyPathError {
    .permission(.accessibilityNotGranted)
  }

  /// Create an input monitoring permission error
  public static var inputMonitoringNotGranted: KeyPathError {
    .permission(.inputMonitoringNotGranted)
  }

  /// Create a UDP timeout error
  public static var udpTimeout: KeyPathError {
    .communication(.timeout)
  }

  /// Create a driver not loaded error
  public static func driverNotLoaded(_ driver: String) -> KeyPathError {
    .system(.driverNotLoaded(driver: driver))
  }
}

// MARK: - Equatable Conformance

extension KeyPathError: Equatable {
  public static func == (lhs: KeyPathError, rhs: KeyPathError) -> Bool {
    switch (lhs, rhs) {
    case (.configuration(let l), .configuration(let r)):
      l == r
    case (.process(let l), .process(let r)):
      l == r
    case (.permission(let l), .permission(let r)):
      l == r
    case (.system(let l), .system(let r)):
      l == r
    case (.communication(let l), .communication(let r)):
      l == r
    case (.coordination(let l), .coordination(let r)):
      l == r
    case (.logging(let l), .logging(let r)):
      l == r
    default:
      false
    }
  }
}

// ... existing code ...
