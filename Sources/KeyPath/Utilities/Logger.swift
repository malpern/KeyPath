import Foundation

class AppLogger {
    static let shared = AppLogger()

    // MARK: - Configuration

    private let maxLogSize: Int = 5 * 1024 * 1024 // 5MB max log file size (keeps total under 10MB)
    private let maxLogFiles: Int = 3 // Keep 3 rotated logs (current + 2 backups)
    private let bufferSize: Int = 100 // Buffer up to 100 messages before writing
    private let flushInterval: TimeInterval = 5.0 // Auto-flush every 5 seconds

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

    private init() {
        // Set log directory to project directory for easy access during development
        let projectPath = "/Volumes/FlashGordon/Dropbox/code/KeyPath"
        if FileManager.default.fileExists(atPath: projectPath) {
            logDirectory = projectPath + "/logs"
        } else {
            // Fallback to user directory if project path not available
            logDirectory = NSHomeDirectory() + "/Library/Logs/KeyPath"
        }

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

    deinit {
        flushTimer?.invalidate()
        flushBuffer()
    }

    // MARK: - Public Interface

    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(timestamp)] [\(fileName):\(line) \(function)] \(message)"

        // Always print to console for immediate feedback during development
        Swift.print(logMessage)

        // Write immediately for debugging (no buffering)
        bufferQueue.async {
            self.writeLogMessageDirectly(logMessage)
        }
    }

    /// Force flush all buffered messages to disk
    func flushBuffer() {
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

    /// Get current log file size in bytes
    func getCurrentLogSize() -> Int {
        guard FileManager.default.fileExists(atPath: logPath) else { return 0 }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logPath)
            return attributes[.size] as? Int ?? 0
        } catch {
            return 0
        }
    }

    /// Get total size of all log files (current + rotated)
    func getTotalLogSize() -> Int {
        var totalSize = getCurrentLogSize()

        for backupIndex in 1 ..< maxLogFiles {
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

    /// Clear all log files (useful for testing or manual cleanup)
    func clearAllLogs() {
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
