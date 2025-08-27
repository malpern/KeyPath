#!/usr/bin/env swift

import Foundation

print("=== Test Admin Restart via AppleScript ===")
print("This tests the exact approach KeyPath should use for admin restart")

// This simulates the restartServicesWithAdmin method
let serviceIDs = ["com.keypath.kanata"]
let cmds = serviceIDs.map { "launchctl kickstart -k system/\($0)" }.joined(separator: " && ")
let script = """
do shell script "\(cmds)" with administrator privileges with prompt "KeyPath needs to restart failing system services."
"""

print("AppleScript command:")
print(script)
print()

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-e", script]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

print("Running command...")
do {
    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    print("Exit code: \(task.terminationStatus)")
    print("Output: '\(output)'")

    if task.terminationStatus == 0 {
        print("✅ Admin restart succeeded!")

        // Wait and check service status
        print("\nWaiting 3 seconds for service to restart...")
        Thread.sleep(forTimeInterval: 3.0)

        // Check service status
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        checkTask.arguments = ["list", "com.keypath.kanata"]

        let checkPipe = Pipe()
        checkTask.standardOutput = checkPipe
        checkTask.standardError = checkPipe

        try checkTask.run()
        checkTask.waitUntilExit()

        if checkTask.terminationStatus == 0 {
            let data = checkPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            func extractInt(from text: String, pattern: String) -> Int? {
                do {
                    let rx = try NSRegularExpression(pattern: pattern)
                    let nsRange = NSRange(text.startIndex..., in: text)
                    guard let match = rx.firstMatch(in: text, range: nsRange),
                          match.numberOfRanges >= 2,
                          let range = Range(match.range(at: 1), in: text) else {
                        return nil
                    }
                    return Int(text[range])
                } catch {
                    return nil
                }
            }

            let exitCode = extractInt(from: output, pattern: #""LastExitStatus"\s*=\s*(-?\d+);"#) ?? 0
            let pid = extractInt(from: output, pattern: #""PID"\s*=\s*([0-9]+);"#)

            print("After restart:")
            print("PID: \(pid?.description ?? "nil")")
            print("Exit Code: \(exitCode)")

            let isHealthy = (pid != nil && exitCode == 0)
            if isHealthy {
                print("🎉 SUCCESS: Kanata service is now healthy!")
                print("   The admin restart approach works correctly.")
                print("   Issue must be in KeyPath wizard logic or method calling.")
            } else {
                print("⚠️  Service restarted but still unhealthy.")
                print("   This suggests a deeper issue with kanata configuration.")
            }
        }

    } else {
        print("❌ Admin restart failed")
        if output.contains("User canceled") || output.contains("cancelled") {
            print("   User canceled the admin prompt")
        } else {
            print("   Other error: \(output)")
        }
    }

} catch {
    print("Error running AppleScript: \(error)")
}

print("\n=== Analysis ===")
print("If admin restart succeeded:")
print("- The AppleScript approach works")
print("- Issue is in KeyPath wizard not calling this method")
print("If admin restart failed:")
print("- Need to check AppleScript command construction")
print("- Or there's a deeper system issue")
