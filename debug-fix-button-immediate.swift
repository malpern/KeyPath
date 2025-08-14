#!/usr/bin/env swift

import Foundation

print("🔍 DEBUG: Checking KeyPath logs for Fix button execution")
print(String(repeating: "=", count: 60))

// Check log directory
let logDir = NSHomeDirectory() + "/Library/Logs/KeyPath"
let logFile = logDir + "/keypath-debug.log"

print("📁 Log directory: \(logDir)")
print("📄 Log file path: \(logFile)")

if FileManager.default.fileExists(atPath: logDir) {
    print("✅ Log directory exists")

    if FileManager.default.fileExists(atPath: logFile) {
        print("✅ Log file exists")

        // Read the last 100 lines of the log file to see recent activity
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        task.arguments = ["-n", "100", logFile]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("\n📋 RECENT LOG CONTENT (last 100 lines):")
                print(String(repeating: "-", count: 50))
                print(output)
                print(String(repeating: "-", count: 50))

                // Check for specific debug patterns
                if output.contains("*** FIX BUTTON CLICKED ***") {
                    print("✅ FOUND: Fix button execution detected!")
                } else {
                    print("❌ NOT FOUND: No Fix button execution detected")
                }

                if output.contains("*** ENHANCED DEBUGGING ***") {
                    print("✅ FOUND: Enhanced debugging is active")
                } else {
                    print("❌ NOT FOUND: Enhanced debugging not detected")
                }

                if output.contains("restartUnhealthyServices") {
                    print("✅ FOUND: Service restart attempts detected")
                } else {
                    print("❌ NOT FOUND: No service restart attempts")
                }

            } else {
                print("❌ Could not read log file content")
            }
        } catch {
            print("❌ Error reading log file: \(error)")
        }
    } else {
        print("❌ Log file does not exist")
    }

    // List all files in log directory
    do {
        let files = try FileManager.default.contentsOfDirectory(atPath: logDir)
        print("\n📁 Files in log directory:")
        for file in files {
            print("  - \(file)")
        }
    } catch {
        print("❌ Error listing log directory: \(error)")
    }

} else {
    print("❌ Log directory does not exist")
}

print("\n🔍 NEXT STEPS:")
print("1. If log file exists with content, check for our debug patterns")
print("2. If no logs found, the Fix button may not be executing")
print("3. If logs exist but no debug patterns, there may be an exception")
print("4. Check Console.app with 'KeyPath' filter for any crash logs")

print("\n" + String(repeating: "=", count: 60))
print("✅ Log analysis complete")
