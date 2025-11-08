#!/usr/bin/env swift

import Foundation

// Debug the current wizard logic step by step
print("=== Debug Current KeyPath Wizard Logic ===")

// Step 1: Check service status exactly like the wizard does
print("\n1. Service Status Detection:")

let services = [
    ("com.keypath.kanata", "Kanata", false),
    ("com.keypath.vhiddaemon", "VHID Daemon", false),
    ("com.keypath.vhidmanager", "VHID Manager", true), // true = one-shot
]

var loadedCount = 0
var healthyCount = 0
var loadedButUnhealthyCount = 0

for (serviceID, name, isOneShot) in services {
    print("\n--- \(name) (\(serviceID)) ---")

    // Test loaded status
    let loadedTask = Process()
    loadedTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    loadedTask.arguments = ["list", serviceID]

    let pipe = Pipe()
    loadedTask.standardOutput = pipe
    loadedTask.standardError = pipe

    do {
        try loadedTask.run()
        loadedTask.waitUntilExit()

        let isLoaded = loadedTask.terminationStatus == 0
        print("Loaded: \(isLoaded)")

        if isLoaded {
            loadedCount += 1

            // Parse health
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let lastExitCode = extractInt(from: output, pattern: #""LastExitStatus"\s*=\s*(-?\d+);"#) ?? 0
            let pid = extractInt(from: output, pattern: #""PID"\s*=\s*([0-9]+);"#)
            let hasPID = (pid != nil)

            print("PID: \(pid?.description ?? "nil")")
            print("Last Exit Code: \(lastExitCode)")

            // Apply health logic
            let healthy: Bool = isOneShot
                ? (lastExitCode == 0) // one-shot OK without PID if exit was clean
                : (hasPID && lastExitCode == 0) // keep-alive services must be running and clean

            print("Healthy: \(healthy)")

            if healthy {
                healthyCount += 1
            } else {
                loadedButUnhealthyCount += 1
                print("⚠️  This service is LOADED BUT UNHEALTHY")
            }
        } else {
            print("❌ Not loaded")
        }

    } catch {
        print("Error: \(error)")
    }
}

print("\n=== Summary ===")
print("Total services: 3")
print("Loaded: \(loadedCount)")
print("Healthy: \(healthyCount)")
print("Loaded but unhealthy: \(loadedButUnhealthyCount)")

// Step 2: Determine wizard classification
print("\n2. Wizard Classification Logic:")

let allServicesHealthy = (healthyCount == 3)
let allServicesLoaded = (loadedCount == 3)
let hasLoadedButUnhealthy = (loadedButUnhealthyCount > 0)

print("allServicesHealthy: \(allServicesHealthy)")
print("allServicesLoaded: \(allServicesLoaded)")
print("hasLoadedButUnhealthy: \(hasLoadedButUnhealthy)")

if allServicesHealthy {
    print("🟢 Result: Services should show as INSTALLED (green)")
} else if hasLoadedButUnhealthy {
    print("🟡 Result: Should show 'LaunchDaemon Services Failing'")
    print("   Fix action: 'Restart failing system services'")
    print("   Auto-fix: restartUnhealthyServices")
} else {
    print("🔴 Result: Should show 'LaunchDaemon Services Not Installed'")
    print("   Fix action: 'Install LaunchDaemon services'")
    print("   Auto-fix: installLaunchDaemonServices")
}

// Helper function
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

print("\n3. Next Steps to Debug:")
print("- Launch KeyPath and check if wizard shows the expected classification above")
print("- Check logs in ~/Library/Logs/KeyPath/ for ComponentDetector messages")
print("- Try clicking Fix and see if it triggers the right auto-fix action")
print("- Look for admin password prompts during the fix")
