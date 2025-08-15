#!/usr/bin/env swift

import Foundation

print("🔧 KeyPath Permission Fix - Adding kanata to Input Monitoring")
print(String(repeating: "=", count: 60))
print()
print("ISSUE IDENTIFIED:")
print("Kanata service is crashing with 'IOHIDDeviceOpen error: privilege violation'")
print("This means the kanata binary needs Input Monitoring permission.")
print()

// Check current permission status
let task = Process()
task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
task.arguments = ["print", "system/com.keypath.kanata"]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()

    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    if output.contains("successive crashes") {
        let crashes = output.components(separatedBy: "\n")
            .first { $0.contains("successive crashes") }?
            .trimmingCharacters(in: .whitespaces)
        print("⚠️  Service status: \(crashes ?? "Has crashes")")
    }

    if output.contains("state = running") {
        print("✅ Service is running (but crashing frequently)")
    }
} catch {
    print("❌ Could not check service status")
}

print()
print("SOLUTION:")
print("1. Open System Settings (System Preferences on older macOS)")
print("2. Go to Privacy & Security")
print("3. Click on 'Input Monitoring' in the left sidebar")
print("4. Click the '+' button to add an app")
print("5. Navigate to: /usr/local/bin/kanata")
print("6. Select 'kanata' and click 'Open'")
print("7. Make sure the checkbox next to 'kanata' is enabled")
print()
print("AUTOMATED OPTION:")
print("Run this command to open System Settings directly to Input Monitoring:")
print()
print("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'")
print()
print("After granting permission, restart the kanata service:")
print("sudo launchctl kickstart -k system/com.keypath.kanata")
print()

// Try to open System Settings automatically
let openTask = Process()
openTask.executableURL = URL(fileURLWithPath: "/usr/bin/open")
openTask.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]

print("🚀 Opening System Settings to Input Monitoring...")

do {
    try openTask.run()
    openTask.waitUntilExit()

    if openTask.terminationStatus == 0 {
        print("✅ System Settings should now be open to Input Monitoring")
        print("   Add '/usr/local/bin/kanata' and enable it")
    } else {
        print("❌ Could not open System Settings automatically")
        print("   Please open it manually using the steps above")
    }
} catch {
    print("❌ Could not open System Settings: \(error)")
}

print()
print("After completing these steps:")
print("• The red X in KeyPath wizard should turn green")
print("• Kanata service will stop crashing")
print("• Keyboard remapping will work properly")
