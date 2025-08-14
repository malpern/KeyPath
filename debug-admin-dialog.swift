#!/usr/bin/env swift

import Foundation

print("🔧 Testing admin password dialog directly...")

// Test the exact osascript command that LaunchDaemonInstaller uses
let testCommand = """
echo "test content" > /tmp/test-keypath.plist
"""

let escapedCommand = testCommand.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "\"", with: "\\\"")

let osascriptCode = """
do shell script "\(escapedCommand)" with administrator privileges
"""

print("🔍 Testing osascript command:")
print(osascriptCode)
print("")

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-e", osascriptCode]

let pipe = Pipe()
process.standardOutput = pipe
process.standardError = pipe

do {
    try process.run()
    process.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? "No output"
    
    print("🔍 Exit code: \(process.terminationStatus)")
    print("🔍 Output: \(output)")
    
    if process.terminationStatus == 0 {
        print("✅ osascript command succeeded")
        
        // Check if test file was created
        if FileManager.default.fileExists(atPath: "/tmp/test-keypath.plist") {
            print("✅ Test file created successfully")
            try? FileManager.default.removeItem(atPath: "/tmp/test-keypath.plist")
        } else {
            print("❌ Test file was not created")
        }
    } else {
        print("❌ osascript command failed")
    }
    
} catch {
    print("❌ Error running osascript: \(error)")
}