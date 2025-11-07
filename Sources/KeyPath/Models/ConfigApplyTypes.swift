import Foundation

/// Commands describing user-intent edits to configuration.
public enum ConfigEditCommand: Equatable, Sendable {
    case addSimpleMapping(SimpleMapping)
    case removeSimpleMapping(id: UUID)
    case toggleSimpleMapping(id: UUID, enabled: Bool)
    /// Replace on-disk config text wholesale (escape hatch).
    case replaceConfigText(String)
}

/// Result of applying a config edit through the pipeline.
public struct ApplyResult: Equatable, Sendable {
    public let success: Bool
    public let rolledBack: Bool
    public let error: ConfigError?
    public let diagnostics: ConfigDiagnostics?

    public init(success: Bool,
                rolledBack: Bool = false,
                error: ConfigError? = nil,
                diagnostics: ConfigDiagnostics? = nil) {
        self.success = success
        self.rolledBack = rolledBack
        self.error = error
        self.diagnostics = diagnostics
    }
}

/// Typed error taxonomy for the apply pipeline.
public enum ConfigError: Error, Equatable, Sendable {
    case preWriteValidationFailed(message: String)
    case writeFailed(message: String)
    case postWriteValidationFailed(message: String)
    case reloadFailed(message: String)
    case readinessTimeout(message: String)
    case healthCheckFailed(message: String)
}

/// Structured diagnostics to aid user feedback and logging.
public struct ConfigDiagnostics: Equatable, Sendable {
    public let configPathBefore: String?
    public let configPathAfter: String?
    public let mappingCountBefore: Int?
    public let mappingCountAfter: Int?
    public let validationOutput: String?
    public let timestamp: Date

    public init(configPathBefore: String? = nil,
                configPathAfter: String? = nil,
                mappingCountBefore: Int? = nil,
                mappingCountAfter: Int? = nil,
                validationOutput: String? = nil,
                timestamp: Date = Date()) {
        self.configPathBefore = configPathBefore
        self.configPathAfter = configPathAfter
        self.mappingCountBefore = mappingCountBefore
        self.mappingCountAfter = mappingCountAfter
        self.validationOutput = validationOutput
        self.timestamp = timestamp
    }
}
