#!/usr/bin/env swift

import Foundation

print("🔧 Testing KeyPath app's ability to show admin dialogs...")
print("This simulates what happens when KeyPath calls osascript")
print("")

// Test the exact same approach KeyPath uses
let testCommand = "echo 'KeyPath admin dialog test successful'"
let osascriptCode = """
do shell script "\(testCommand)" with administrator privileges with prompt "KeyPath admin dialog test - if you see this dialog, the fix worked!"
"""

print("🔍 Executing osascript from Swift process...")
print("AppleScript code:")
print("  \(osascriptCode)")
print("")

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-e", osascriptCode]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    print("🔍 Results:")
    print("  Exit code: \(task.terminationStatus)")
    print("  Output: '\(output.trimmingCharacters(in: .whitespacesAndNewlines))'")
    print("")

    if task.terminationStatus == 0 {
        print("✅ SUCCESS: osascript admin dialog worked!")
        print("   If you saw the admin password dialog, KeyPath should now work too.")
    } else {
        print("❌ FAILED: osascript admin dialog failed")

        if output.contains("User canceled") {
            print("   → User canceled the dialog (this means dialog appeared)")
        } else if output.contains("execution error") {
            print("   → AppleScript execution error")
        } else if output.isEmpty {
            print("   → No output - possible sandbox/permission issue")
        } else {
            print("   → Unexpected error: \(output)")
        }
    }

} catch {
    print("❌ ERROR: Failed to execute osascript: \(error)")
}

print("")
print("📝 Next step: If this worked, open KeyPath and test the 'Fix' button")
print("   open /Applications/KeyPath.app")
