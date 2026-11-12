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
        /// Multiple rule collections map the same key in the same layer
        case mappingConflicts(conflicts: [MappingConflictInfo])
    }

    /// Describes a conflict where multiple collections map the same key
    public struct MappingConflictInfo: Equatable, Sendable {
        public let inputKey: String
        public let layer: String
        public let conflictingCollections: [String]
        /// Per-collection descriptions of what each does with the key on hold.
        /// e.g., ["Home Row Mods: hold → rsft", "Home Row Layer Toggles: hold → (layer-while-held fun)"]
        public let holdDescriptions: [String]

        public init(
            inputKey: String,
            layer: String,
            conflictingCollections: [String],
            holdDescriptions: [String] = []
        ) {
            self.inputKey = inputKey
            self.layer = layer
            self.conflictingCollections = conflictingCollections
            self.holdDescriptions = holdDescriptions
        }

        public var description: String {
            let collections = conflictingCollections.joined(separator: "\" and \"")
            return "Key '\(inputKey)' is mapped in both \"\(collections)\" (layer: \(layer))"
        }

        /// User-friendly explanation of the conflict and resolution options
        public var userExplanation: String {
            let collections = conflictingCollections.joined(separator: " and ")
            var explanation = String(localized: "\(collections) both configure the \"\(inputKey)\" key with different behaviors.")

            if !holdDescriptions.isEmpty {
                explanation += " " + holdDescriptions.joined(separator: "; ") + "."
            }

            explanation += " " + String(localized: "A key can only have one action assigned.")
            explanation += " " + String(localized: "Either change the key assignments so they don't overlap, or disable one.")

            return explanation
        }
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
            String(localized: "Configuration operation failed")
        case .process:
            String(localized: "Process lifecycle operation failed")
        case .permission:
            String(localized: "Permission or security check failed")
        case .system:
            String(localized: "System-level operation failed")
        case .communication:
            String(localized: "Communication with service failed")
        case .coordination:
            String(localized: "Coordination or state management failed")
        case .logging:
            String(localized: "Logging operation failed")
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .configuration(.fileNotFound):
            String(localized: "Check that the configuration file exists and the path is correct")
        case .configuration(.validationFailed):
            String(localized: "Review the configuration syntax and fix any validation errors")
        case .permission(.accessibilityNotGranted):
            String(localized: "Grant \(AccessibilityPermissionPresentation.current.name) permission in System Settings > Privacy & Security")
        case .process(.notRunning):
            String(localized: "Start the Kanata service before performing this operation")
        case .process(.launchAgentNotFound):
            String(localized: "Run the installation wizard to install required components")
        case .communication(.timeout):
            String(localized: "Check that the Kanata service is running and restart if necessary")
        case .communication(.notAuthenticated):
            String(localized: "Restart the service to refresh authentication")
        case .system(.driverNotLoaded):
            String(localized: "Run the installation wizard to install the Karabiner driver")
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
            String(localized: "Configuration file not found: \(path)")
        case let .loadFailed(reason):
            String(localized: "Failed to load configuration: \(reason)")
        case let .saveFailed(reason):
            String(localized: "Failed to save configuration: \(reason)")
        case let .validationFailed(errors):
            String(localized: "Configuration validation failed: \(errors.joined(separator: ", "))")
        case let .invalidFormat(reason):
            String(localized: "Invalid configuration format: \(reason)")
        case let .watchingFailed(reason):
            String(localized: "Failed to watch configuration file: \(reason)")
        case let .backupFailed(reason):
            String(localized: "Failed to create backup: \(reason)")
        case let .backupRestoreFailed(reason):
            String(localized: "Failed to restore from backup: \(reason)")
        case let .backupListFailed(reason):
            String(localized: "Failed to list backups: \(reason)")
        case let .parseError(line, message):
            if let line {
                String(localized: "Parse error at line \(line): \(message)")
            } else {
                String(localized: "Parse error: \(message)")
            }
        case .backupNotFound:
            String(localized: "No backup configuration found")
        case let .corruptedFormat(details):
            String(localized: "Configuration file is corrupted: \(details)")
        case let .repairFailed(reason):
            String(localized: "Failed to repair configuration: \(reason)")
        case let .mappingConflicts(conflicts):
            conflicts.map(\.userExplanation).joined(separator: "\n\n")
        }
    }

    private func processErrorDescription(_ error: ProcessError) -> String {
        switch error {
        case let .startFailed(reason):
            String(localized: "Process start failed: \(reason)")
        case let .stopFailed(underlyingError):
            String(localized: "Process stop failed: \(underlyingError)")
        case let .terminateFailed(underlyingError):
            String(localized: "Process termination failed: \(underlyingError)")
        case .notRunning:
            String(localized: "Process is not running")
        case .alreadyRunning:
            String(localized: "Process is already running")
        case let .launchAgentLoadFailed(reason):
            String(localized: "Failed to load launch agent: \(reason)")
        case let .launchAgentUnloadFailed(reason):
            String(localized: "Failed to unload launch agent: \(reason)")
        case .launchAgentNotFound:
            String(localized: "Launch agent not found")
        case let .stateTransitionFailed(from, to):
            String(localized: "State transition failed from \(from) to \(to)")
        case .noManager:
            String(localized: "No manager available")
        }
    }

    private func permissionErrorDescription(_ error: PermissionError) -> String {
        switch error {
        case .accessibilityNotGranted:
            String(localized: "\(AccessibilityPermissionPresentation.current.name) permission not granted")
        case .notificationAuthorizationFailed:
            String(localized: "Notification authorization failed")
        case .oracleInitializationFailed:
            String(localized: "Permission oracle initialization failed")
        case let .keychainSaveFailed(status):
            String(localized: "Keychain save failed with status: \(String(status))")
        case let .keychainLoadFailed(status):
            String(localized: "Keychain load failed with status: \(String(status))")
        case let .keychainDeleteFailed(status):
            String(localized: "Keychain delete failed with status: \(String(status))")
        case let .privilegedOperationFailed(operation, reason):
            String(localized: "Privileged operation '\(operation)' failed: \(reason)")
        }
    }

    private func systemErrorDescription(_ error: SystemError) -> String {
        switch error {
        case .eventTapCreationFailed:
            String(localized: "Failed to create event tap")
        case .eventTapEnableFailed:
            String(localized: "Failed to enable event tap")
        case let .eventProcessingFailed(reason):
            String(localized: "Event processing failed: \(reason)")
        case let .outputSynthesisFailed(reason):
            String(localized: "Output synthesis failed: \(reason)")
        case let .invalidKeyCode(code):
            String(localized: "Invalid key code: \(String(code))")
        case .deviceNotFound:
            String(localized: "Device not found")
        case let .driverNotLoaded(driver):
            String(localized: "Driver not loaded: \(driver)")
        }
    }

    private func communicationErrorDescription(_ error: CommunicationError) -> String {
        switch error {
        case .timeout:
            String(localized: "Communication timeout")
        case .noResponse:
            String(localized: "No response received from server")
        case .invalidPort:
            String(localized: "Invalid port number")
        case .invalidResponse:
            String(localized: "Invalid response from server")
        case .notAuthenticated:
            String(localized: "Not authenticated")
        case let .payloadTooLarge(size):
            String(localized: "Payload too large: \(String(size)) bytes")
        case let .connectionFailed(reason):
            String(localized: "Connection failed: \(reason)")
        case .serializationFailed:
            String(localized: "Failed to serialize data")
        case .deserializationFailed:
            String(localized: "Failed to deserialize response")
        }
    }

    private func coordinationErrorDescription(_ error: CoordinationError) -> String {
        switch error {
        case let .invalidState(expected, actual):
            String(localized: "Invalid state: expected \(expected), got \(actual)")
        case .operationCancelled:
            String(localized: "Operation cancelled")
        case let .recordingFailed(reason):
            String(localized: "Recording failed: \(reason)")
        case let .systemDetectionFailed(component, reason):
            String(localized: "System detection failed for \(component): \(reason)")
        case let .conflictDetected(service):
            String(localized: "Conflict detected with \(service)")
        }
    }

    private func loggingErrorDescription(_ error: LoggingError) -> String {
        switch error {
        case let .fileCreationFailed(path):
            String(localized: "Failed to create log file: \(path)")
        case let .writeFailed(reason):
            String(localized: "Log write failed: \(reason)")
        case let .logRotationFailed(reason):
            String(localized: "Log rotation failed: \(reason)")
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
