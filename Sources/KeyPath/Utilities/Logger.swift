import Foundation

class AppLogger {
  static let shared = AppLogger()
  private var logDirectory: String
  private let logFileName = "keypath-debug.log"
  private var logPath: String {
    "\(logDirectory)/\(logFileName)"
  }

  private let dateFormatter: DateFormatter

  private init() {
    // Set log directory to user's home directory for reliable access
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
  }

  func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    let timestamp = dateFormatter.string(from: Date())
    let fileName = (file as NSString).lastPathComponent

    let logMessage = "[\(timestamp)] [\(fileName):\(line) \(function)] \(message)\n"

    // Also print to console for live debugging during development
    Swift.print(logMessage, terminator: "")

    // Append to log file
    if let data = logMessage.data(using: .utf8) {
      if FileManager.default.fileExists(atPath: logPath) {
        if let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
          fileHandle.seekToEndOfFile()
          fileHandle.write(data)
          fileHandle.closeFile()
        }
      } else {
        try? data.write(to: URL(fileURLWithPath: logPath))
      }
    }
  }
}
