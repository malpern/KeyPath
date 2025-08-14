#!/usr/bin/env swift

import Foundation

print("🔍 Testing admin prompt behavior...")

// Test if KEYPATH_TEST_MODE is set
let testMode = ProcessInfo.processInfo.environment["KEYPATH_TEST_MODE"] == "1"
print("KEYPATH_TEST_MODE: \(testMode ? "ENABLED (this will skip osascript!)" : "disabled")")

// Test a simple osascript command
print("\n📞 Testing simple osascript call...")

let simpleCommand = "echo 'Hello from admin prompt'"
let osascriptCommand = """
do shell script "\(simpleCommand)" with administrator privileges with prompt "Test admin access"
"""

print("Command to execute:")
print(osascriptCommand)
print()

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-e", osascriptCommand]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    print("🚀 Executing osascript...")
    try task.run()
    print("✅ osascript.run() succeeded")
    task.waitUntilExit()
    print("📊 Exit status: \(task.terminationStatus)")
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    print("📤 Output: '\(output)'")
    
    if task.terminationStatus == 0 {
        print("✅ SUCCESS: Admin prompt should have appeared")
    } else {
        print("❌ FAILED: Admin prompt did not work properly")
        print("❌ This suggests osascript is failing before showing the dialog")
    }
} catch {
    print("❌ ERROR: Failed to run osascript: \(error)")
}

print("\n🔍 Environment check:")
print("PATH: \(ProcessInfo.processInfo.environment["PATH"] ?? "not set")")
print("USER: \(ProcessInfo.processInfo.environment["USER"] ?? "not set")")
print("Current working directory: \(FileManager.default.currentDirectoryPath)")