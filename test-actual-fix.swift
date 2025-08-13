#!/usr/bin/env swift

import Foundation

// Test what happens when we run the actual restart command that the fix would use
print("=== Test Actual Fix Command ===")
print("This simulates what KeyPath should do when you click 'Fix'")

// The fix should run: launchctl kickstart -k system/com.keypath.kanata
print("\n1. Testing the actual restart command:")
print("Command: launchctl kickstart -k system/com.keypath.kanata")

let task = Process()
task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
task.arguments = ["kickstart", "-k", "system/com.keypath.kanata"]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    
    print("Exit code: \(task.terminationStatus)")
    print("Output: \(output)")
    
    if task.terminationStatus == 0 {
        print("✅ Command succeeded - service should be restarted")
    } else {
        print("❌ Command failed - this might be why the fix doesn't work")
        if output.contains("authorization") || output.contains("privileges") {
            print("   Issue: Command needs admin privileges")
            print("   KeyPath should prompt for admin password via AppleScript")
        }
    }
    
} catch {
    print("Error running command: \(error)")
}

// Wait a moment for the service to restart, then check status
print("\n2. Waiting 2 seconds for service to restart...")
Thread.sleep(forTimeInterval: 2.0)

print("\n3. Checking service status after restart attempt:")
let checkTask = Process()
checkTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
checkTask.arguments = ["list", "com.keypath.kanata"]

let checkPipe = Pipe()
checkTask.standardOutput = checkPipe
checkTask.standardError = checkPipe

do {
    try checkTask.run()
    checkTask.waitUntilExit()
    
    if checkTask.terminationStatus == 0 {
        let data = checkPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        // Parse new status
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
        
        let newExitCode = extractInt(from: output, pattern: #""LastExitStatus"\s*=\s*(-?\d+);"#) ?? 0
        let newPid = extractInt(from: output, pattern: #""PID"\s*=\s*([0-9]+);"#)
        
        print("New PID: \(newPid?.description ?? "nil")")
        print("New Exit Code: \(newExitCode)")
        
        let isHealthy = (newPid != nil && newExitCode == 0)
        print("Now Healthy: \(isHealthy)")
        
        if isHealthy {
            print("🎉 SUCCESS: Service is now running healthy!")
        } else {
            print("⚠️  Service still unhealthy after restart attempt")
        }
    }
} catch {
    print("Error checking status: \(error)")
}

print("\n=== Conclusion ===")
print("If the command failed due to privileges:")
print("- KeyPath should show admin password prompt")
print("- If user cancels, fix should fail with clear message")
print("If command succeeded but service still unhealthy:")
print("- There might be a deeper configuration issue")
print("- Check kanata binary location and config file")