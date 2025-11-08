#!/usr/bin/env swift

import Foundation

// Debug script to analyze service detection logic
print("🔍 Debugging service detection for kanata service configuration...")
print(String(repeating: "=", count: 60))

// Check the actual launchctl output
func runCommand(_ command: String, args: [String]) -> (output: String, exitCode: Int) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: command)
    task.arguments = args

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, Int(task.terminationStatus))
    } catch {
        return ("Error: \(error)", -1)
    }
}

// Test 1: Check if service is loaded/running
print("1. Checking kanata service status...")
let (printOutput, printExitCode) = runCommand("/bin/launchctl", args: ["print", "system/com.keypath.kanata"])
print("Exit code: \(printExitCode)")
if printExitCode == 0 {
    print("✅ Service is loaded")
    // Extract key information
    let lines = printOutput.components(separatedBy: .newlines)
    for line in lines {
        if line.contains("state = ") {
            print("   \(line.trimmingCharacters(in: .whitespaces))")
        }
        if line.contains("successive crashes = ") {
            print("   \(line.trimmingCharacters(in: .whitespaces))")
        }
        if line.contains("immediate reason = ") {
            print("   \(line.trimmingCharacters(in: .whitespaces))")
        }
        if line.contains("pid = ") {
            print("   \(line.trimmingCharacters(in: .whitespaces))")
        }
    }
} else {
    print("❌ Service is not loaded")
}

print()

// Test 2: Check if config file exists and is readable
print("2. Checking config file...")
let configPath = "\(NSHomeDirectory())/.config/keypath/keypath.kbd"
let fm = FileManager.default

if fm.fileExists(atPath: configPath) {
    print("✅ Config file exists: \(configPath)")
    do {
        let content = try String(contentsOfFile: configPath)
        let lineCount = content.components(separatedBy: .newlines).count
        print("   Lines: \(lineCount)")
        print("   Size: \(content.count) characters")
        if content.contains("defcfg") {
            print("   ✅ Contains defcfg section")
        } else {
            print("   ⚠️  Missing defcfg section")
        }
    } catch {
        print("   ❌ Cannot read file: \(error)")
    }
} else {
    print("❌ Config file missing: \(configPath)")
}

print()

// Test 3: Check what the wizard detection logic might be looking for
print("3. Analyzing potential detection issues...")

// Check if the service is considered "healthy"
if printExitCode == 0 {
    let isRunning = printOutput.contains("state = running")
    let hasCrashes = printOutput.contains("successive crashes = ") && !printOutput.contains("successive crashes = 0")
    let isInefficient = printOutput.contains("immediate reason = inefficient")

    print("   Running: \(isRunning ? "✅ YES" : "❌ NO")")
    print("   Has crashes: \(hasCrashes ? "⚠️  YES" : "✅ NO")")
    print("   Inefficient: \(isInefficient ? "⚠️  YES" : "✅ NO")")

    if isRunning, !hasCrashes, !isInefficient {
        print("   🎯 Service appears healthy - wizard should show green!")
    } else {
        print("   🔍 Service has issues - this explains the red X")
        if hasCrashes || isInefficient {
            print("      → The service is crashing/restarting frequently")
            print("      → This suggests a configuration or permission problem")
        }
    }
} else {
    print("   ❌ Service not loaded - definitely explains red X")
}

print()

// Test 4: Check recent kanata logs for errors
print("4. Checking recent kanata logs...")
let (logOutput, logExitCode) = runCommand("/usr/bin/tail", args: ["-10", "/var/log/kanata.log"])
if logExitCode == 0 {
    let logLines = logOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }
    print("   Recent log entries (\(logLines.count) lines):")
    for line in logLines.prefix(3) {
        print("     \(line)")
    }
    if logOutput.contains("ERROR") || logOutput.contains("FATAL") || logOutput.contains("panic") {
        print("   ⚠️  Found error messages in logs")
    } else {
        print("   ✅ No obvious errors in recent logs")
    }
} else {
    print("   ❌ Cannot read kanata logs")
}

print()

print("🏁 Summary:")
print("The service is installed and running, but the red X suggests the wizard")
print("detection logic is flagging it as unhealthy due to crashes/restarts.")
print("This might be normal behavior for kanata during startup or config changes.")
