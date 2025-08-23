#!/usr/bin/env swift

import Foundation

fileprivate extension String {
    func firstMatchInt(pattern: String) -> Int? {
        do {
            let rx = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(startIndex..., in: self)
            guard let m = rx.firstMatch(in: self, range: nsRange), m.numberOfRanges >= 2,
                  let range = Range(m.range(at: 1), in: self)
            else {
                return nil
            }
            return Int(self[range])
        } catch {
            return nil
        }
    }
}

// Test the improved parsing on actual service output
let task = Process()
task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
task.arguments = ["list", "com.keypath.kanata"]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    print("=== Improved Service Health Detection Test ===")
    print("Exit Code:", task.terminationStatus)

    if task.terminationStatus == 0 {
        print("Service is loaded. Testing improved parsing...")

        // Test the improved regex parsing
        let lastExitCode = output.firstMatchInt(pattern: #""LastExitStatus"\s*=\s*(-?\d+);"#) ?? 0
        let pid = output.firstMatchInt(pattern: #""PID"\s*=\s*([0-9]+);"#)
        let hasPID = (pid != nil)

        print("Last Exit Code: \(lastExitCode)")
        print("PID: \(pid?.description ?? "nil")")
        print("Has PID: \(hasPID)")

        // Test KeepAlive semantics (Kanata is keep-alive, not one-shot)
        let isOneShot = false // Kanata is keep-alive
        let healthy: Bool = isOneShot
            ? (lastExitCode == 0) // one-shot OK without PID if exit was clean
            : (hasPID && lastExitCode == 0) // keep-alive services must be running and clean

        print("Is One-Shot: \(isOneShot)")
        print("Healthy: \(healthy)")

        if healthy {
            print("✅ Service is healthy")
        } else {
            print("❌ Service is UNHEALTHY")
            print("   Reason: \(isOneShot ? "Bad exit code" : "Not running or bad exit code")")
            print("   This will show 'LaunchDaemon Services Failing' with 'Restart failing system services' fix")
        }
    } else {
        print("❌ Service not loaded")
    }

} catch {
    print("Error: \(error)")
}
