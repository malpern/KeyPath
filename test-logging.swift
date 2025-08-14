#!/usr/bin/env swift

import Foundation

// Simple test script for the new logging system
print("🧪 Testing New Logging System")
print("=============================")

// Copy the essential parts of AppLogger for testing
class TestLogger {
  static let shared = TestLogger()

  private let maxLogSize: Int = 1024  // 1KB for quick testing
  private let maxLogFiles: Int = 3
  private let bufferSize: Int = 5  // Small buffer for quick testing

  private var logDirectory: String
  private let logFileName = "test-log.log"
  private var logPath: String {
    "\(logDirectory)/\(logFileName)"
  }

  private var messageBuffer: [String] = []

  private init() {
    logDirectory = NSTemporaryDirectory() + "keypath-test"

    do {
      try FileManager.default.createDirectory(
        atPath: logDirectory,
        withIntermediateDirectories: true,
        attributes: nil
      )
      print("✅ Created test log directory: \(logDirectory)")
    } catch {
      print("❌ Failed to create log directory: \(error)")
    }
  }

  func log(_ message: String) {
    let logMessage = "[TEST] \(message)"
    print(logMessage)  // Console output

    messageBuffer.append(logMessage)

    if messageBuffer.count >= bufferSize {
      flush()
    }
  }

  func flush() {
    guard !messageBuffer.isEmpty else { return }

    // Check if rotation needed
    if getCurrentLogSize() >= maxLogSize {
      rotateLogFiles()
    }

    let messages = messageBuffer.joined(separator: "\n") + "\n"
    messageBuffer.removeAll()

    if let data = messages.data(using: .utf8) {
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

  func getCurrentLogSize() -> Int {
    guard FileManager.default.fileExists(atPath: logPath) else { return 0 }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: logPath)
      return attributes[.size] as? Int ?? 0
    } catch {
      return 0
    }
  }

  func rotateLogFiles() {
    let fileManager = FileManager.default

    // Move current log to .1 backup
    if fileManager.fileExists(atPath: logPath) {
      try? fileManager.moveItem(atPath: logPath, toPath: "\(logPath).1")
      print("🔄 Rotated log file (size limit reached)")
    }
  }

  func getLogInfo() -> String {
    let currentSize = getCurrentLogSize()
    let backupExists = FileManager.default.fileExists(atPath: "\(logPath).1")
    return "Current log: \(currentSize) bytes, Backup exists: \(backupExists)"
  }
}

// Test the logging system
let logger = TestLogger.shared

print("\n📝 Testing basic logging...")
for i in 1...10 {
  logger.log("Test message #\(i) - This is a test of the logging system")
}

print("\n📊 After 10 messages: \(logger.getLogInfo())")

logger.flush()
print("📊 After flush: \(logger.getLogInfo())")

print("\n📝 Testing rotation...")
for i in 11...25 {
  logger.log("Long test message #\(i) - This message is designed to be longer to trigger log rotation when the file size exceeds the limit")
}

logger.flush()
print("📊 After more messages: \(logger.getLogInfo())")

print("\n✅ Logging test complete! Check the temporary directory for results.")
