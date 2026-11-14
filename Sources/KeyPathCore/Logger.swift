import Foundation
import os
import Synchronization

/// Log severity levels for AppLogger
public enum AppLogLevel: Int, CaseIterable, Sendable {
    case trace = 0
    case debug = 1
    case info = 2
    case warn = 3
    case error = 4

    /// Whether this level should be logged based on minimum level
    func shouldLog(minimumLevel: AppLogLevel) -> Bool {
        rawValue >= minimumLevel.rawValue
    }

    /// Default minimum level based on build configuration
    static var defaultMinimumLevel: AppLogLevel {
        #if DEBUG
            return .debug
        #else
            return .info
        #endif
    }
}

public final class AppLogger: Sendable {
    public static let shared = AppLogger()

    // MARK: - Configuration

    private let maxLogSize: Int = 5 * 1024 * 1024
    private let maxLogFiles: Int = 3 // Keep 3 rotated logs (current + 2 backups)

    private struct Options: Sendable {
        var minimumLevel: AppLogLevel
        var enableConsoleLogging: Bool
    }

    private let options: Mutex<Options>
    private let logDirectory: Mutex<String>
    private let logFileName = "keypath-debug.log"
    private var logPath: String {
        "\(logDirectory.withLock { $0 })/\(logFileName)"
    }

    private let dateFormatter: DateFormatter
    private let fileQueue = DispatchQueue(label: "com.keypath.logger", qos: .utility)

    public init(
        minimumLevel: AppLogLevel? = nil,
        enableConsoleLogging: Bool? = nil
    ) {
        // Prefer the environment override, then the parameter, then the build default.
        let configuredLevel: AppLogLevel = if let envLevel = ProcessInfo.processInfo.environment["KEYPATH_LOG_LEVEL"],
                                              let levelInt = Int(envLevel),
                                              let level = AppLogLevel(rawValue: levelInt)
        {
            level
        } else {
            minimumLevel ?? AppLogLevel.defaultMinimumLevel
        }

        // Console logging (default: true in debug, false in release)
        #if DEBUG
            let consoleEnabled = enableConsoleLogging ?? true
        #else
            let consoleEnabled = enableConsoleLogging ?? false
        #endif

        options = Mutex(Options(minimumLevel: configuredLevel, enableConsoleLogging: consoleEnabled))

        // Use test overrides before the standard macOS log directory.
        // AppPaths redirects to the per-process test sandbox under test, so a
        // plain `swift test` never writes into the developer's real debug log.
        // The directory overrides exist for tests and are not read in release builds.
        var directory = AppPaths.logsDirectory.path
        #if DEBUG
            if let explicitOverride = ProcessInfo.processInfo.environment["KEYPATH_LOG_DIR_OVERRIDE"],
               !explicitOverride.isEmpty
            {
                directory = explicitOverride
            } else if let homeOverride = ProcessInfo.processInfo.environment["KEYPATH_HOME_DIR_OVERRIDE"],
                      !homeOverride.isEmpty
            {
                directory = homeOverride + "/Library/Logs/KeyPath"
            }
        #endif

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Ensure log directory exists
        do {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            // Fallback to temporary directory if creation fails
            print(
                "Error creating log directory at \(directory): \(error.localizedDescription). Falling back to temporary directory."
            )
            directory = NSTemporaryDirectory()
        }

        logDirectory = Mutex(directory)
    }

    /// Update minimum log level at runtime
    public func setMinimumLevel(_ level: AppLogLevel) {
        fileQueue.async {
            self.options.withLock { $0.minimumLevel = level }
        }
    }

    public func setConsoleLoggingEnabled(_ enabled: Bool) {
        options.withLock { $0.enableConsoleLogging = enabled }
    }

    /// Override the log directory (primarily for integration tests that sandbox HOME)
    public func overrideLogDirectory(_ directory: String) {
        guard !directory.isEmpty else { return }
        fileQueue.sync {
            logDirectory.withLock { $0 = directory }
            do {
                try FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                print(
                    "Error creating override log directory at \(directory): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Returns the current log directory path (useful for tests that override logging destinations)
    public func currentLogDirectory() -> String {
        fileQueue.sync { logDirectory.withLock { $0 } }
    }

    // MARK: - Public Interface

    /// Log a message with optional level (defaults to info for backward compatibility)
    public func log(
        _ message: String,
        level: AppLogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let options = options.withLock { $0 }
        guard level.shouldLog(minimumLevel: options.minimumLevel) else {
            return
        }

        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let levelPrefix = levelPrefix(for: level)
        let logMessage = "[\(timestamp)] [\(levelPrefix)] [\(fileName):\(line) \(function)] \(message)"

        // Print to console if enabled
        if options.enableConsoleLogging {
            Swift.print(logMessage)
        }

        // The unified log too, so Console can filter by subsystem, category (the
        // source file) and level. The file log above stays the diagnostics record.
        Self.writeToSystemLog(message, level: level, category: (fileName as NSString).deletingPathExtension)

        fileQueue.async {
            self.appendToFile(logMessage)
        }
    }

    /// Convenience methods for each log level
    public func trace(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(message, level: .trace, file: file, function: function, line: line)
    }

    public func debug(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    public func info(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    /// A message that names a key the user pressed. Debug builds log it at
    /// debug level; release builds never write it, at any log level, because a
    /// log of key presses is a log of what the user typed.
    public func keystroke(
        _ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        #if DEBUG
            log(message(), level: .debug, file: file, function: function, line: line)
        #endif
    }

    public func warn(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(message, level: .warn, file: file, function: function, line: line)
    }

    /// Log an expected fixture/setup diagnostic as a warning in normal use, but
    /// downgrade it to debug during quiet test runs.
    public func warnUnlessQuietTest(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        let level: AppLogLevel = TestEnvironment.shouldQuietExpectedTestDiagnostics ? .debug : .warn
        log(message, level: level, file: file, function: function, line: line)
    }

    /// Log an expected failure-path diagnostic as an error in normal use, but
    /// downgrade it to debug during quiet test runs.
    public func errorUnlessQuietTest(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        let level: AppLogLevel = TestEnvironment.shouldQuietExpectedTestDiagnostics ? .debug : .error
        log(message, level: level, file: file, function: function, line: line)
    }

    public func error(
        _ message: String, file: String = #file, function: String = #function, line: Int = #line
    ) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    // MARK: - System log

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.keypath.KeyPath"
    private static let systemLoggers = Mutex<[String: os.Logger]>([:])

    /// The text is private at every level: lines at any level can carry key codes,
    /// app names or pieces of the user's config. Console still shows the level,
    /// category (source file), time and process; the text needs a logging profile.
    /// The file log keeps the full text for diagnostics.
    static func writeToSystemLog(_ message: String, level: AppLogLevel, category: String) {
        let logger = systemLoggers.withLock { loggers in
            if let existing = loggers[category] { return existing }
            let created = os.Logger(subsystem: subsystem, category: category)
            loggers[category] = created
            return created
        }
        switch level {
        case .trace, .debug: logger.debug("\(message, privacy: .private)")
        case .info: logger.info("\(message, privacy: .private)")
        case .warn: logger.warning("\(message, privacy: .private)")
        case .error: logger.error("\(message, privacy: .private)")
        }
    }

    // MARK: - Private Helpers

    private func levelPrefix(for level: AppLogLevel) -> String {
        switch level {
        case .trace: "TRACE"
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warn: "WARN"
        case .error: "ERROR"
        }
    }

    /// Wait for pending file writes to complete.
    public func flushBuffer() {
        fileQueue.sync {}
    }

    // MARK: - File Operations

    private func appendToFile(_ message: String) {
        // Check if rotation is needed before writing
        rotateIfNeeded()

        let logEntry = message + "\n"
        guard let data = logEntry.data(using: .utf8) else { return }

        // Write to file
        if FileManager.default.fileExists(atPath: logPath) {
            // Append to existing file
            do {
                let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
                try fileHandle.close()
            } catch {
                // Fallback: try to create new file
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        } else {
            // Create new file
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }

    private func rotateIfNeeded() {
        guard FileManager.default.fileExists(atPath: logPath) else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logPath)
            let fileSize = attributes[.size] as? Int ?? 0

            if fileSize >= maxLogSize {
                rotateLogFiles()
            }
        } catch {
            // If we can't check file size, assume it's fine
            Swift.print("Logger: Error checking log file size: \(error)")
        }
    }

    private func rotateLogFiles() {
        let fileManager = FileManager.default

        // Remove oldest backup if it exists
        let oldestBackup = "\(logPath).\(maxLogFiles - 1)"
        if fileManager.fileExists(atPath: oldestBackup) {
            try? fileManager.removeItem(atPath: oldestBackup)
        }

        // Rotate existing backups (shift numbers up)
        for fileIndex in stride(from: maxLogFiles - 2, through: 1, by: -1) {
            let oldPath = "\(logPath).\(fileIndex)"
            let newPath = "\(logPath).\(fileIndex + 1)"

            if fileManager.fileExists(atPath: oldPath) {
                try? fileManager.moveItem(atPath: oldPath, toPath: newPath)
            }
        }

        // Move current log to .1 backup
        if fileManager.fileExists(atPath: logPath) {
            try? fileManager.moveItem(atPath: logPath, toPath: "\(logPath).1")
        }

        Swift.print("Logger: Rotated log files (max size \(maxLogSize / 1024 / 1024)MB reached)")
    }

    // MARK: - Utility Methods

    public func getCurrentLogSize() -> Int {
        fileQueue.sync { Self.fileSize(at: logPath) }
    }

    public func getTotalLogSize() -> Int {
        fileQueue.sync {
            let path = logPath
            return (1 ..< maxLogFiles).reduce(Self.fileSize(at: path)) { total, backupIndex in
                total + Self.fileSize(at: "\(path).\(backupIndex)")
            }
        }
    }

    private static func fileSize(at path: String) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.size] as? Int ?? 0
    }

    public func clearAllLogs() {
        fileQueue.async {
            // Remove all log files
            let fileManager = FileManager.default

            // Remove main log
            if fileManager.fileExists(atPath: self.logPath) {
                try? fileManager.removeItem(atPath: self.logPath)
            }

            // Remove backup logs
            for logIndex in 1 ..< self.maxLogFiles {
                let backupPath = "\(self.logPath).\(logIndex)"
                if fileManager.fileExists(atPath: backupPath) {
                    try? fileManager.removeItem(atPath: backupPath)
                }
            }

            Swift.print("Logger: Cleared all log files")
        }
    }
}
