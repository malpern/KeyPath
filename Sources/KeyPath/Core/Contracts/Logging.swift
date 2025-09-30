import Foundation

/// Protocol defining logging capabilities for KeyPath components.
///
/// This protocol establishes a consistent interface for logging throughout
/// the KeyPath application. It provides the foundation for clean separation
/// between logging functionality and business logic.
///
/// ## Usage
///
/// Logging services implement this protocol to provide different logging
/// backends and behaviors:
///
/// ```swift
/// class FileLogger: Logging {
///     func log(_ message: String, level: LogLevel, category: String?) {
///         let timestamp = dateFormatter.string(from: Date())
///         let formattedMessage = "[\(timestamp)] \(level.prefix) \(category ?? "General"): \(message)"
///         writeToFile(formattedMessage)
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// All methods should be thread-safe as logging can occur from any queue
/// throughout the application.
protocol Logging {
    /// Logs a message with the specified level and optional category.
    ///
    /// This is the core logging method that all other convenience methods
    /// build upon. Implementations should handle formatting, buffering,
    /// and output routing.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - level: The severity level of the message.
    ///   - category: Optional category for organizing log messages.
    func log(_ message: String, level: LogLevel, category: String?)

    /// Flushes any buffered log messages to their destination.
    ///
    /// This method ensures that buffered log messages are written to
    /// their final destination (file, console, etc.) immediately.
    func flush()

    /// Configures the logger with specific settings.
    ///
    /// This method allows runtime configuration of logging behavior
    /// such as log levels, output destinations, and formatting options.
    ///
    /// - Parameter config: The logging configuration to apply.
    func configure(_ config: LoggingConfiguration)
}

/// Extension providing convenience methods and default behaviors.
extension Logging {
    /// Logs a debug message.
    ///
    /// Debug messages are typically used for detailed diagnostic information
    /// that is only relevant during development or troubleshooting.
    ///
    /// - Parameters:
    ///   - message: The debug message to log.
    ///   - category: Optional category for organizing messages.
    func debug(_ message: String, category: String? = nil) {
        log(message, level: .debug, category: category)
    }

    /// Logs an informational message.
    ///
    /// Info messages provide general information about application operation
    /// and are typically shown in production logs.
    ///
    /// - Parameters:
    ///   - message: The informational message to log.
    ///   - category: Optional category for organizing messages.
    func info(_ message: String, category: String? = nil) {
        log(message, level: .info, category: category)
    }

    /// Logs a warning message.
    ///
    /// Warning messages indicate potential issues that don't prevent
    /// operation but should be noted for investigation.
    ///
    /// - Parameters:
    ///   - message: The warning message to log.
    ///   - category: Optional category for organizing messages.
    func warning(_ message: String, category: String? = nil) {
        log(message, level: .warning, category: category)
    }

    /// Logs an error message.
    ///
    /// Error messages indicate failures or issues that impact application
    /// functionality and require attention.
    ///
    /// - Parameters:
    ///   - message: The error message to log.
    ///   - category: Optional category for organizing messages.
    func error(_ message: String, category: String? = nil) {
        log(message, level: .error, category: category)
    }

    /// Logs a critical/fatal message.
    ///
    /// Critical messages indicate severe issues that may cause application
    /// termination or major functionality loss.
    ///
    /// - Parameters:
    ///   - message: The critical message to log.
    ///   - category: Optional category for organizing messages.
    func critical(_ message: String, category: String? = nil) {
        log(message, level: .critical, category: category)
    }

    /// Logs a message using the current AppLogger format (for compatibility).
    ///
    /// This method provides backward compatibility with existing AppLogger.shared.log() calls.
    /// Messages are logged at info level with automatic formatting preservation.
    ///
    /// - Parameter message: The message in AppLogger format (with emojis and tags).
    func log(_ message: String) {
        log(message, level: .info, category: nil)
    }
}

/// Log severity levels.
enum LogLevel: Int, CaseIterable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4

    /// Display name for the log level.
    var name: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARNING"
        case .error: "ERROR"
        case .critical: "CRITICAL"
        }
    }

    /// Short prefix for log formatting.
    var prefix: String {
        switch self {
        case .debug: "🐛"
        case .info: "ℹ️"
        case .warning: "⚠️"
        case .error: "❌"
        case .critical: "🔥"
        }
    }

    /// Whether this level should be logged based on minimum level.
    func shouldLog(minimumLevel: LogLevel) -> Bool {
        rawValue >= minimumLevel.rawValue
    }
}

/// Configuration for logging behavior.
struct LoggingConfiguration: Sendable {
    let minimumLevel: LogLevel
    let enableFileLogging: Bool
    let enableConsoleLogging: Bool
    let maxFileSize: Int
    let maxFiles: Int
    let flushInterval: TimeInterval
    let dateFormat: String

    /// Default configuration matching AppLogger behavior.
    static let `default` = LoggingConfiguration(
        minimumLevel: .debug,
        enableFileLogging: true,
        enableConsoleLogging: true,
        maxFileSize: 5 * 1024 * 1024, // 5MB
        maxFiles: 3,
        flushInterval: 5.0,
        dateFormat: "yyyy-MM-dd HH:mm:ss.SSS"
    )

    /// Configuration for production use (less verbose).
    static let production = LoggingConfiguration(
        minimumLevel: .info,
        enableFileLogging: true,
        enableConsoleLogging: false,
        maxFileSize: 10 * 1024 * 1024, // 10MB
        maxFiles: 5,
        flushInterval: 10.0,
        dateFormat: "yyyy-MM-dd HH:mm:ss"
    )

    /// Configuration for development (most verbose).
    static let development = LoggingConfiguration(
        minimumLevel: .debug,
        enableFileLogging: true,
        enableConsoleLogging: true,
        maxFileSize: 50 * 1024 * 1024, // 50MB
        maxFiles: 2,
        flushInterval: 1.0,
        dateFormat: "HH:mm:ss.SSS"
    )
}

/// Output destinations for log messages.
enum LogDestination: Sendable {
    case file(String)
    case console
    case systemLog
    case custom(String)

    var identifier: String {
        switch self {
        case let .file(path): "file:\(path)"
        case .console: "console"
        case .systemLog: "system"
        case let .custom(name): "custom:\(name)"
        }
    }
}

/// Specialized logging for component-specific needs.
protocol ComponentLogging: Logging {
    /// The component name for this logger.
    var componentName: String { get }

    /// Logs a message with the component name automatically added.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - level: The log level.
    func logForComponent(_ message: String, level: LogLevel)
}

/// Default implementation for component logging.
extension ComponentLogging {
    func logForComponent(_ message: String, level: LogLevel) {
        log(message, level: level, category: componentName)
    }
}

/// Errors related to logging operations.
/// Logging operation errors
///
/// - Deprecated: Use `KeyPathError.logging(...)` instead for consistent error handling
@available(*, deprecated, message: "Use KeyPathError.logging(...) instead")
enum LoggingError: Error, LocalizedError {
    case configurationFailed(String)
    case writeFailed(String)
    case flushFailed(String)
    case destinationUnavailable(LogDestination)

    var errorDescription: String? {
        switch self {
        case let .configurationFailed(reason):
            "Logging configuration failed: \(reason)"
        case let .writeFailed(reason):
            "Log write failed: \(reason)"
        case let .flushFailed(reason):
            "Log flush failed: \(reason)"
        case let .destinationUnavailable(destination):
            "Log destination unavailable: \(destination.identifier)"
        }
    }

    /// Convert to KeyPathError for consistent error handling
    var asKeyPathError: KeyPathError {
        switch self {
        case let .configurationFailed(reason):
            return .logging(.writeFailed(reason: "Configuration failed: \(reason)"))
        case let .writeFailed(reason):
            return .logging(.writeFailed(reason: reason))
        case let .flushFailed(reason):
            return .logging(.writeFailed(reason: "Flush failed: \(reason)"))
        case let .destinationUnavailable(destination):
            return .logging(.fileCreationFailed(path: destination.identifier))
        }
    }
}
