#!/usr/bin/env swift

import Foundation

// Simple test to ensure logging directory works
let logsPath = "/Volumes/FlashGordon/Dropbox/code/KeyPath/logs"
let testLogPath = logsPath + "/test-direct.log"

print("🧪 Testing direct logging to KeyPath logs directory...")

// Ensure directory exists
try? FileManager.default.createDirectory(atPath: logsPath, withIntermediateDirectories: true, attributes: nil)

// Write test log
let message = "Test log entry - \(Date())"
try? message.write(to: URL(fileURLWithPath: testLogPath), atomically: true, encoding: .utf8)

print("✅ Test log written to: \(testLogPath)")
print("📂 Logs directory contents:")

if let contents = try? FileManager.default.contentsOfDirectory(atPath: logsPath) {
    for file in contents {
        print("  - \(file)")
    }
}