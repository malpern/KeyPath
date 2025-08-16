#!/usr/bin/env swift

import Foundation

/// Test script to verify the LaunchDaemon-only architecture fix
print("🧪 Testing KeyPath LaunchDaemon-only architecture...")

// Step 1: Check current Kanata processes
print("\n1️⃣ Checking current Kanata processes...")
let task1 = Process()
task1.executableURL = URL(fileURLWithPath: "/bin/ps")
task1.arguments = ["aux"]
let pipe1 = Pipe()
task1.standardOutput = pipe1

try task1.run()
task1.waitUntilExit()

let data1 = pipe1.fileHandleForReading.readDataToEndOfFile()
let output1 = String(data: data1, encoding: .utf8) ?? ""
let kanataProcesses = output1.components(separatedBy: .newlines).filter {
    $0.contains("kanata") && !$0.contains("grep") && !$0.contains("test-launchdaemon")
}

print("📊 Found \(kanataProcesses.count) Kanata processes:")
for (index, process) in kanataProcesses.enumerated() {
    print("   [\(index)] \(process)")
}

// Step 2: Check LaunchDaemon service status
print("\n2️⃣ Checking LaunchDaemon service status...")
let task2 = Process()
task2.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
task2.arguments = ["launchctl", "print", "system/com.keypath.kanata"]
let pipe2 = Pipe()
task2.standardOutput = pipe2
task2.standardError = pipe2

try task2.run()
task2.waitUntilExit()

let data2 = pipe2.fileHandleForReading.readDataToEndOfFile()
let output2 = String(data: data2, encoding: .utf8) ?? ""

if task2.terminationStatus == 0 {
    print("✅ LaunchDaemon service is loaded")

    // Extract PID if available
    let lines = output2.components(separatedBy: .newlines)
    for line in lines {
        if line.contains("pid =") {
            print("📍 Service PID: \(line.trimmingCharacters(in: .whitespaces))")
            break
        }
    }
} else {
    print("❌ LaunchDaemon service is not loaded")
    print("Output: \(output2)")
}

// Step 3: Test a simple config change to verify hot reload works
print("\n3️⃣ Testing config hot reload...")
let configPath = "\(NSHomeDirectory())/.config/keypath/keypath.kbd"

if FileManager.default.fileExists(atPath: configPath) {
    print("📄 Config file exists at: \(configPath)")

    // Read current config
    let currentConfig = try String(contentsOfFile: configPath)
    print("📖 Current config:")
    print(currentConfig)

    // Add a timestamp comment to trigger file watcher
    let timestamp = Date().timeIntervalSince1970
    let newConfig = currentConfig + "\n;; Test reload at \(timestamp)\n"

    print("\n🔄 Triggering hot reload by updating config...")
    try newConfig.write(toFile: configPath, atomically: true, encoding: .utf8)

    print("✅ Config updated - check Kanata logs for hot reload messages")
    print("💡 Expected log: 'Config file changed' followed by 'Live reload successful'")

} else {
    print("⚠️ Config file not found - cannot test hot reload")
}

print("\n🎯 LaunchDaemon architecture test complete!")
print("🔍 Check /var/log/kanata.log for hot reload results")
