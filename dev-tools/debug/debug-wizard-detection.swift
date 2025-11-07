#!/usr/bin/env swift

import Foundation

// Debug script to test what the wizard should actually be detecting
print("=== KeyPath Wizard Debug - Service Detection ===")

// Test the service status detection logic manually
let services = ["com.keypath.kanata", "com.keypath.vhiddaemon", "com.keypath.vhidmanager"]

for serviceID in services {
    print("\n--- Testing \(serviceID) ---")

    // 1. Test if service is loaded (launchctl list serviceID returns 0)
    let loadedTask = Process()
    loadedTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    loadedTask.arguments = ["list", serviceID]

    let loadedPipe = Pipe()
    loadedTask.standardOutput = loadedPipe
    loadedTask.standardError = loadedPipe

    do {
        try loadedTask.run()
        loadedTask.waitUntilExit()

        let isLoaded = loadedTask.terminationStatus == 0
        print("Loaded: \(isLoaded)")

        if isLoaded {
            // 2. Test health detection
            let data = loadedPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Use our improved regex parsing
            let lastExitCode = extractInt(from: output, pattern: #""LastExitStatus"\s*=\s*(-?\d+);"#) ?? 0
            let pid = extractInt(from: output, pattern: #""PID"\s*=\s*([0-9]+);"#)
            let hasPID = (pid != nil)

            print("PID: \(pid?.description ?? "nil")")
            print("Last Exit Code: \(lastExitCode)")
            print("Has PID: \(hasPID)")

            // Apply KeepAlive semantics
            let isOneShot = (serviceID == "com.keypath.vhidmanager")
            let healthy: Bool = isOneShot
                ? (lastExitCode == 0) // one-shot OK without PID if exit was clean
                : (hasPID && lastExitCode == 0) // keep-alive services must be running and clean

            print("One-shot service: \(isOneShot)")
            print("Healthy: \(healthy)")

            // Determine what the wizard should show
            if healthy {
                print("🔵 Should show: INSTALLED (green)")
            } else if isLoaded {
                print("🟡 Should show: 'LaunchDaemon Services Failing' (red)")
                print("   Fix action: 'Restart failing system services'")
            } else {
                print("🔴 Should show: 'LaunchDaemon Services Not Installed' (red)")
                print("   Fix action: 'Install LaunchDaemon services'")
            }
        } else {
            print("🔴 Service not loaded - should show as 'Not Installed'")
        }

    } catch {
        print("Error checking service: \(error)")
    }
}

// Helper function for regex extraction
func extractInt(from text: String, pattern: String) -> Int? {
    do {
        let rx = try NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = rx.firstMatch(in: text, range: nsRange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int(text[range])
    } catch {
        return nil
    }
}

print("\n=== Expected Wizard Behavior ===")
print("If all services are loaded but unhealthy (exit code != 0 or no PID for keep-alive):")
print("- Component status should be: 'LaunchDaemon Services Failing'")
print("- Fix button should say: 'Restart failing system services'")
print("- Clicking fix should use launchctl kickstart with admin prompt")
