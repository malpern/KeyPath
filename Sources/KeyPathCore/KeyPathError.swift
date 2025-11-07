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
        case let .configuration(error):
            configurationErrorDescription(error)
        case let .process(error):
            processErrorDescription(error)
        case let .permission(error):
            permissionErrorDescription(error)
        case let .system(error):
            systemErrorDescription(error)
        case let .communication(error):
            communicationErrorDescription(error)
        case let .coordination(error):
            coordinationErrorDescription(error)
        case let .logging(error):
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
        case let .fileNotFound(path):
            "Configuration file not found: \(path)"
        case let .loadFailed(reason):
            "Failed to load configuration: \(reason)"
        case let .saveFailed(reason):
            "Failed to save configuration: \(reason)"
        case let .validationFailed(errors):
            "Configuration validation failed: \(errors.joined(separator: ", "))"
        case let .invalidFormat(reason):
            "Invalid configuration format: \(reason)"
        case let .watchingFailed(reason):
            "Failed to watch configuration file: \(reason)"
        case let .backupFailed(reason):
            "Failed to create backup: \(reason)"
        case let .backupRestoreFailed(reason):
            "Failed to restore from backup: \(reason)"
        case let .backupListFailed(reason):
            "Failed to list backups: \(reason)"
        case let .parseError(line, message):
            if let line {
                "Parse error at line \(line): \(message)"
            } else {
                "Parse error: \(message)"
            }
        case .backupNotFound:
            "No backup configuration found"
        case let .corruptedFormat(details):
            "Configuration file is corrupted: \(details)"
        case let .repairFailed(reason):
            "Failed to repair configuration: \(reason)"
        }
    }

    private func processErrorDescription(_ error: ProcessError) -> String {
        switch error {
        case let .startFailed(reason):
            "Process start failed: \(reason)"
        case let .stopFailed(underlyingError):
            "Process stop failed: \(underlyingError)"
        case let .terminateFailed(underlyingError):
            "Process termination failed: \(underlyingError)"
        case .notRunning:
            "Process is not running"
        case .alreadyRunning:
            "Process is already running"
        case let .launchAgentLoadFailed(reason):
            "Failed to load launch agent: \(reason)"
        case let .launchAgentUnloadFailed(reason):
            "Failed to unload launch agent: \(reason)"
        case .launchAgentNotFound:
            "Launch agent not found"
        case let .stateTransitionFailed(from, to):
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
        case let .keychainSaveFailed(status):
            "Keychain save failed with status: \(status)"
        case let .keychainLoadFailed(status):
            "Keychain load failed with status: \(status)"
        case let .keychainDeleteFailed(status):
            "Keychain delete failed with status: \(status)"
        case let .privilegedOperationFailed(operation, reason):
            "Privileged operation '\(operation)' failed: \(reason)"
        }
    }

    private func systemErrorDescription(_ error: SystemError) -> String {
        switch error {
        case .eventTapCreationFailed:
            "Failed to create event tap"
        case .eventTapEnableFailed:
            "Failed to enable event tap"
        case let .eventProcessingFailed(reason):
            "Event processing failed: \(reason)"
        case let .outputSynthesisFailed(reason):
            "Output synthesis failed: \(reason)"
        case let .invalidKeyCode(code):
            "Invalid key code: \(code)"
        case .deviceNotFound:
            "Device not found"
        case let .driverNotLoaded(driver):
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
        case let .payloadTooLarge(size):
            "Payload too large: \(size) bytes"
        case let .connectionFailed(reason):
            "Connection failed: \(reason)"
        case .serializationFailed:
            "Failed to serialize data"
        case .deserializationFailed:
            "Failed to deserialize response"
        }
    }

    private func coordinationErrorDescription(_ error: CoordinationError) -> String {
        switch error {
        case let .invalidState(expected, actual):
            "Invalid state: expected \(expected), got \(actual)"
        case .operationCancelled:
            "Operation cancelled"
        case let .recordingFailed(reason):
            "Recording failed: \(reason)"
        case let .systemDetectionFailed(component, reason):
            "System detection failed for \(component): \(reason)"
        case let .conflictDetected(service):
            "Conflict detected with \(service)"
        }
    }

    private func loggingErrorDescription(_ error: LoggingError) -> String {
        switch error {
        case let .fileCreationFailed(path):
            "Failed to create log file: \(path)"
        case let .writeFailed(reason):
            "Log write failed: \(reason)"
        case let .logRotationFailed(reason):
            "Log rotation failed: \(reason)"
        }
    }
}

// MARK: - Convenience Constructors

public extension KeyPathError {
    /// Create a configuration file not found error
    static func configFileNotFound(_ path: String) -> KeyPathError {
        .configuration(.fileNotFound(path: path))
    }

    /// Create a process start failed error
    static func processStartFailed(_ reason: String) -> KeyPathError {
        .process(.startFailed(reason: reason))
    }

    /// Create an accessibility permission error
    static var accessibilityNotGranted: KeyPathError {
        .permission(.accessibilityNotGranted)
    }

    /// Create an input monitoring permission error
    static var inputMonitoringNotGranted: KeyPathError {
        .permission(.inputMonitoringNotGranted)
    }

    /// Create a UDP timeout error
    static var udpTimeout: KeyPathError {
        .communication(.timeout)
    }

    /// Create a driver not loaded error
    static func driverNotLoaded(_ driver: String) -> KeyPathError {
        .system(.driverNotLoaded(driver: driver))
    }
}

// MARK: - Equatable Conformance

extension KeyPathError: Equatable {
    public static func == (lhs: KeyPathError, rhs: KeyPathError) -> Bool {
        switch (lhs, rhs) {
        case let (.configuration(l), .configuration(r)):
            l == r
        case let (.process(l), .process(r)):
            l == r
        case let (.permission(l), .permission(r)):
            l == r
        case let (.system(l), .system(r)):
            l == r
        case let (.communication(l), .communication(r)):
            l == r
        case let (.coordination(l), .coordination(r)):
            l == r
        case let (.logging(l), .logging(r)):
            l == r
        default:
            false
        }
    }
}

// ... existing code ...
