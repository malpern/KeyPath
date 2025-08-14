#!/usr/bin/env swift

import Foundation

print("🔍 DEBUG: Fix Button Execution Flow Analysis")
print(String(repeating: "=", count: 60))

// This script helps debug the complete Fix button execution flow
// by adding comprehensive logging and checking all error message paths

let sourcesPath = "/Volumes/FlashGordon/Dropbox/code/KeyPath/Sources/KeyPath"

// Key files to examine for Fix button execution flow
let keyFiles = [
    "InstallationWizard/UI/InstallationWizardView.swift",
    "InstallationWizard/Core/WizardAutoFixer.swift",
    "InstallationWizard/Core/WizardAsyncOperationManager.swift",
    "InstallationWizard/Core/LaunchDaemonInstaller.swift"
]

print("\n📋 LOGGING ANALYSIS PLAN:")
print("1. Check all paths where Fix button errors are generated")
print("2. Verify error message routing through the system")
print("3. Add comprehensive logging to track execution")
print("4. Identify why user is seeing generic error")

print("\n🔍 CHECKING CURRENT ERROR MESSAGE PATHS:")

// Check for all "Failed to restart" patterns
let grep1 = Process()
grep1.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
grep1.arguments = ["-r", "-n", "Failed to restart", sourcesPath]
grep1.standardOutput = Pipe()

do {
    try grep1.run()
    grep1.waitUntilExit()

    if let data = try (grep1.standardOutput as? Pipe)?.fileHandleForReading.readToEnd(),
       let output = String(data: data, encoding: .utf8) {
        print("FOUND 'Failed to restart' patterns:")
        print(output)
    }
} catch {
    print("Error running grep: \(error)")
}

print("\n🔍 CHECKING AUTO-FIX ACTION MAPPING:")

// Check how .launchDaemonServicesUnhealthy maps to .restartUnhealthyServices
let grep2 = Process()
grep2.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
grep2.arguments = ["-r", "-n", "launchDaemonServicesUnhealthy", sourcesPath]
grep2.standardOutput = Pipe()

do {
    try grep2.run()
    grep2.waitUntilExit()

    if let data = try (grep2.standardOutput as? Pipe)?.fileHandleForReading.readToEnd(),
       let output = String(data: data, encoding: .utf8) {
        print("FOUND launchDaemonServicesUnhealthy mapping:")
        print(output)
    }
} catch {
    print("Error running grep: \(error)")
}

print("\n🔍 CHECKING TOAST MANAGER ERROR DISPLAY:")

// Check toastManager.showError patterns
let grep3 = Process()
grep3.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
grep3.arguments = ["-r", "-n", "toastManager.showError", sourcesPath]
grep3.standardOutput = Pipe()

do {
    try grep3.run()
    grep3.waitUntilExit()

    if let data = try (grep3.standardOutput as? Pipe)?.fileHandleForReading.readToEnd(),
       let output = String(data: data, encoding: .utf8) {
        print("FOUND toastManager.showError patterns:")
        print(output)
    }
} catch {
    print("Error running grep: \(error)")
}

print("\n💡 DEBUGGING RECOMMENDATIONS:")
print("1. Check Console.app logs during Fix button click")
print("2. Look for lines containing '[AutoFixer]' and '[NewWizard]'")
print("3. Verify which error message generation path is being taken")
print("4. Check if our getDetailedErrorMessage() method is actually called")

print("\n🚨 CRITICAL QUESTIONS TO ANSWER:")
print("1. Is restartUnhealthyServices() being called?")
print("2. Is getDetailedErrorMessage() being called with correct action?")
print("3. Is the error message being overridden somewhere else?")
print("4. Are we hitting a fallback error path we missed?")

print("\n🔧 NEXT STEPS:")
print("1. Add console logging to track every step")
print("2. Build and deploy with enhanced logging")
print("3. Test Fix button and examine logs")
print("4. Fix any remaining error message routing issues")

print("\n" + String(repeating: "=", count: 60))
print("✅ Analysis complete. Ready to add comprehensive logging.")
