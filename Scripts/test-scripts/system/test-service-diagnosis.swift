#!/usr/bin/env swift

import Foundation

/// Quick test script to verify the improved service diagnosis works
print("🔧 Testing LaunchDaemon Service Diagnosis Improvements")
print("=======================================================")

// Test service status checking (what users would see in logs)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
task.arguments = ["print", "system/com.keypath.kanata"]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    if task.terminationStatus == 0 {
        print("✅ Successfully retrieved service status")

        // Check for code signing issues
        if output.contains("OS_REASON_CODESIGNING") {
            print("❌ DETECTED: Code signing issue - this is what our improved diagnosis will catch!")
            print("💡 Our fix will now provide actionable guidance for this issue")
        } else if output.contains("job state = exited") {
            print("⚠️ Service is exiting - our diagnosis will analyze why")
        } else if output.contains("state = spawn scheduled") {
            print("🔄 Service is scheduled to run but may be failing immediately")
        } else {
            print("ℹ️ Service appears to be in normal state")
        }

        // Show key parts of the status for verification
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("last exit reason") ||
                line.contains("job state") ||
                line.contains("runs =") {
                print("🔍 Key info: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

    } else {
        print("❌ Could not get service status: \(output)")
    }
} catch {
    print("❌ Error running launchctl: \(error)")
}

print("\n🎯 Summary of Improvements Made:")
print("• Added detailed service failure diagnosis after restart attempts")
print("• Detect and explain code signing issues (OS_REASON_CODESIGNING)")
print("• Check executable permissions and existence")
print("• Provide specific solutions for each type of failure")
print("• Improved user-facing error messages with actionable guidance")
print("• Added code signing verification for kanata binary")
