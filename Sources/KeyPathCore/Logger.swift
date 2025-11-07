import Foundation

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

public final class AppLogger {
  public static let shared = AppLogger()

  // MARK: - Configuration

  private let maxLogSize: Int = 5 * 1024 * 1024  // 5MB max log file size (keeps total under 10MB)
  private let maxLogFiles: Int = 3  // Keep 3 rotated logs (current + 2 backups)
  private let bufferSize: Int = 100  // Buffer up to 100 messages before writing
  private let flushInterval: TimeInterval = 5.0  // Auto-flush every 5 seconds

  /// Minimum log level to output (respects build configuration)
  private var minimumLevel: AppLogLevel
  private let levelLock = NSLock()

  private func getMinimumLevel() -> AppLogLevel {
    levelLock.lock()
    defer { levelLock.unlock() }
    return minimumLevel
  }

  private func setMinimumLevelInternal(_ level: AppLogLevel) {
    levelLock.lock()
    defer { levelLock.unlock() }
    minimumLevel = level
  }

  /// Whether console logging is enabled (default: true in debug, false in release)
  private let enableConsoleLogging: Bool

  // MARK: - State

  private var logDirectory: String
  private let logFileName = "keypath-debug.log"
  private var logPath: String {
    "\(logDirectory)/\(logFileName)"
  }

  private let dateFormatter: DateFormatter
  private var messageBuffer: [String] = []
  private let bufferQueue = DispatchQueue(label: "com.keypath.logger", qos: .utility)
  private var flushTimer: Timer?

  public init(
    minimumLevel: AppLogLevel? = nil,
    enableConsoleLogging: Bool? = nil
  ) {
    // Determine minimum log level (environment variable override > parameter > default)
    if let envLevel = ProcessInfo.processInfo.environment["KEYPATH_LOG_LEVEL"],
      let levelInt = Int(envLevel),
      let level = AppLogLevel(rawValue: levelInt) {
      self.minimumLevel = level
    } else {
      self.minimumLevel = minimumLevel ?? AppLogLevel.defaultMinimumLevel
    }

    // Console logging (default: true in debug, false in release)
    #if DEBUG
      self.enableConsoleLogging = enableConsoleLogging ?? true
    #else
      self.enableConsoleLogging = enableConsoleLogging ?? false
    #endif

    // Use standard macOS app logs directory
    logDirectory = NSHomeDirectory() + "/Library/Logs/KeyPath"

    dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

    // Ensure log directory exists
    do {
      try FileManager.default.createDirectory(
        atPath: logDirectory,
        withIntermediateDirectories: true,
        attributes: nil
      )
    } catch {
      // Fallback to temporary directory if creation fails
      print(
        "Error creating log directory at \(logDirectory): \(error.localizedDescription). Falling back to temporary directory."
      )
      logDirectory = NSTemporaryDirectory()
    }

    // Start automatic flush timer
    DispatchQueue.main.async {
      self.flushTimer = Timer.scheduledTimer(withTimeInterval: self.flushInterval, repeats: true) {
        _ in
        self.flushBuffer()
      }
    }
  }

  /// Update minimum log level at runtime
  public func setMinimumLevel(_ level: AppLogLevel) {
    bufferQueue.async {
      self.setMinimumLevelInternal(level)
    }
  }

  deinit {
    flushTimer?.invalidate()
    flushBuffer()
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
    // Check if this level should be logged
    guard level.shouldLog(minimumLevel: getMinimumLevel()) else {
      return
    }

    let timestamp = dateFormatter.string(from: Date())
    let fileName = (file as NSString).lastPathComponent
    let levelPrefix = levelPrefix(for: level)
    let logMessage = "[\(timestamp)] [\(levelPrefix)] [\(fileName):\(line) \(function)] \(message)"

    // Print to console if enabled
    if enableConsoleLogging {
      Swift.print(logMessage)
    }

    // Write immediately for debugging (no buffering)
    bufferQueue.async {
      self.writeLogMessageDirectly(logMessage)
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

  public func warn(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
  ) {
    log(message, level: .warn, file: file, function: function, line: line)
  }

  public func error(
    _ message: String, file: String = #file, function: String = #function, line: Int = #line
  ) {
    log(message, level: .error, file: file, function: function, line: line)
  }

  // MARK: - Private Helpers

  private func levelPrefix(for level: AppLogLevel) -> String {
    switch level {
    case .trace: return "TRACE"
    case .debug: return "DEBUG"
    case .info: return "INFO"
    case .warn: return "WARN"
    case .error: return "ERROR"
    }
  }

  /// Force flush all buffered messages to disk
  public func flushBuffer() {
    bufferQueue.async {
      self.flushBufferUnsafe()
    }
  }

  // MARK: - Private Implementation

  private func flushBufferUnsafe() {
    guard !messageBuffer.isEmpty else { return }

    // Check if rotation is needed before writing
    rotateIfNeeded()

    // Write all buffered messages
    let messages = messageBuffer.joined(separator: "\n") + "\n"
    messageBuffer.removeAll()

    guard let data = messages.data(using: .utf8) else { return }

    // Write to file
    if FileManager.default.fileExists(atPath: logPath) {
      // Append to existing file
      do {
        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        fileHandle.closeFile()
      } catch {
        // Fallback: try to create new file
        try? data.write(to: URL(fileURLWithPath: logPath))
      }
    } else {
      // Create new file
      try? data.write(to: URL(fileURLWithPath: logPath))
    }
  }

  /// Write a single log message directly to file (no buffering)
  private func writeLogMessageDirectly(_ message: String) {
    // Check if rotation is needed before writing
    rotateIfNeeded()

    let logEntry = message + "\n"
    guard let data = logEntry.data(using: .utf8) else { return }

    // Write to file
    if FileManager.default.fileExists(atPath: logPath) {
      // Append to existing file
      do {
        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        fileHandle.closeFile()
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
    guard FileManager.default.fileExists(atPath: logPath) else { return 0 }

    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: logPath)
      return attributes[.size] as? Int ?? 0
    } catch {
      return 0
    }
  }

  public func getTotalLogSize() -> Int {
    var totalSize = getCurrentLogSize()

    for backupIndex in 1..<maxLogFiles {
      let backupPath = "\(logPath).\(backupIndex)"
      if FileManager.default.fileExists(atPath: backupPath) {
        do {
          let attributes = try FileManager.default.attributesOfItem(atPath: backupPath)
          totalSize += attributes[.size] as? Int ?? 0
        } catch {
          // Ignore errors for backup files
        }
      }
    }

    return totalSize
  }

  public func clearAllLogs() {
    bufferQueue.async {
      // Clear buffer first
      self.messageBuffer.removeAll()

      // Remove all log files
      let fileManager = FileManager.default

      // Remove main log
      if fileManager.fileExists(atPath: self.logPath) {
        try? fileManager.removeItem(atPath: self.logPath)
      }

      // Remove backup logs
      for logIndex in 1..<self.maxLogFiles {
        let backupPath = "\(self.logPath).\(logIndex)"
        if fileManager.fileExists(atPath: backupPath) {
          try? fileManager.removeItem(atPath: backupPath)
        }
      }

      Swift.print("Logger: Cleared all log files")
    }
  }
}

// AppLogger coordinates its own internal synchronization; mark as unchecked Sendable for Swift 6.
extension AppLogger: @unchecked Sendable {}
