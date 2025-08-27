#!/usr/bin/env swift

// Test script for the new hybrid permission request flow
// Run with: swift test-permission-flow.swift

import Foundation
import IOKit.hid

print("🧪 Testing Hybrid Permission Request Flow")
print("==========================================\n")

// Test 1: Check stale entry detection
print("1️⃣ Testing Stale Entry Detection:")
print("   - Checking for development build paths...")
print("   - Checking for multiple KeyPath installations...")
print("   - Checking for multiple kanata processes...")

let bundlePath = Bundle.main.bundlePath
print("   Current bundle path: \(bundlePath)")

var indicators: [String] = []

// Check if running from development path
if bundlePath.contains(".build/") || bundlePath.contains("DerivedData/") {
    indicators.append("Running from development build location")
}

// Check if KeyPath exists in /Applications
if !bundlePath.hasPrefix("/Applications/") {
    let applicationsPath = "/Applications/KeyPath.app"
    if FileManager.default.fileExists(atPath: applicationsPath) {
        indicators.append("KeyPath exists in /Applications but running from \(bundlePath)")
    }
}

// Check for multiple kanata processes
let task = Process()
task.launchPath = "/bin/sh"
task.arguments = ["-c", "pgrep -x kanata | wc -l"]
let pipe = Pipe()
task.standardOutput = pipe
task.standardError = Pipe()

do {
    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8),
       let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)),
       count > 1 {
        indicators.append("Multiple kanata processes detected (\(count) running)")
    }
} catch {
    print("   ⚠️ Error checking for kanata processes: \(error)")
}

if indicators.isEmpty {
    print("   ✅ No stale entries detected - clean state!")
} else {
    print("   ⚠️ Potential stale entries detected:")
    for indicator in indicators {
        print("      • \(indicator)")
    }
}

print("\n2️⃣ Testing IOHIDRequestAccess Availability:")
if #available(macOS 10.15, *) {
    print("   ✅ IOHIDRequestAccess is available on this system")

    // Check current permission status
    let currentStatus = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    let statusString = switch currentStatus {
    case kIOHIDAccessTypeGranted:
        "Granted"
    case kIOHIDAccessTypeDenied:
        "Denied"
    case kIOHIDAccessTypeUnknown:
        "Unknown"
    default:
        "Other (\(currentStatus))"
    }

    print("   Current Input Monitoring status: \(statusString)")

    if currentStatus != kIOHIDAccessTypeGranted {
        print("\n3️⃣ Testing Permission Request Flow:")
        print("   Based on detection results, the wizard would:")

        if !indicators.isEmpty {
            print("   1. Show cleanup instructions for stale entries")
            print("   2. Guide user to System Settings")
            print("   3. Help remove old entries with warning icons")
            print("   4. Add current KeyPath to permissions")
        } else {
            print("   1. Attempt programmatic request via IOHIDRequestAccess")
            print("   2. Show native permission dialog")
            print("   3. If denied, fall back to manual System Settings flow")
        }
    }
} else {
    print("   ⚠️ IOHIDRequestAccess not available (macOS < 10.15)")
    print("   Will use manual System Settings flow only")
}

print("\n4️⃣ Summary:")
print("   The hybrid approach provides:")
print("   • Streamlined experience for clean installations")
print("   • Clear guidance for cleaning up old entries")
print("   • Automatic fallback for edge cases")
print("   • Better user experience overall")

print("\n✅ Test complete!")
