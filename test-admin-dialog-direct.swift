#!/usr/bin/env swift

import Foundation

print("🔧 Testing direct osascript admin dialog from Swift...")

// Test the simplest possible admin dialog
let simpleTest = """
do shell script "echo 'test successful'" with administrator privileges
"""

print("🔍 Executing simple osascript command...")
print("Command: osascript -e '\(simpleTest)'")

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-e", simpleTest]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    
    print("🔍 Exit code: \(task.terminationStatus)")
    print("🔍 Output: '\(output.trimmingCharacters(in: .whitespacesAndNewlines))'")
    
    if task.terminationStatus == 0 {
        print("✅ Direct osascript succeeded - admin dialog should have appeared")
    } else {
        print("❌ Direct osascript failed")
        
        // Try to understand why it failed
        if output.contains("User canceled") {
            print("   → User canceled the dialog")
        } else if output.contains("not allowed") {
            print("   → Permission/sandbox issue")
        } else if output.isEmpty {
            print("   → No output - possible sandbox restriction")
        }
    }
    
} catch {
    print("❌ Error executing osascript: \(error)")
}

// Also test with explicit prompt
print("\n🔧 Testing with explicit prompt...")
let promptTest = """
do shell script "echo 'test with prompt'" with administrator privileges with prompt "Test admin dialog"
"""

let task2 = Process()
task2.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task2.arguments = ["-e", promptTest]

let pipe2 = Pipe()
task2.standardOutput = pipe2
task2.standardError = pipe2

do {
    try task2.run()
    task2.waitUntilExit()
    
    let data = pipe2.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    
    print("🔍 Exit code: \(task2.terminationStatus)")
    print("🔍 Output: '\(output.trimmingCharacters(in: .whitespacesAndNewlines))'")
    
    if task2.terminationStatus == 0 {
        print("✅ Prompted osascript succeeded")
    } else {
        print("❌ Prompted osascript failed")
    }
    
} catch {
    print("❌ Error executing prompted osascript: \(error)")
}

print("\n🔧 If neither showed an admin dialog, the issue is likely:")
print("   1. App sandbox restrictions preventing dialogs")
print("   2. Security & Privacy settings blocking the app")
print("   3. Need for specific entitlements or code signing")
print("   4. macOS version-specific restrictions")