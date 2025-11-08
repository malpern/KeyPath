#!/usr/bin/env swift

import Foundation
import ServiceManagement

/// Phase 4: Migration/Rollback Testing
/// Tests migration scenarios between launchctl and SMAppService

print("🔄 Phase 4: Migration/Rollback Testing")
print("=====================================")
print("")

guard #available(macOS 13, *) else {
    print("❌ SMAppService requires macOS 13+")
    exit(1)
}

// Test 1: Check for existing launchctl-managed service
print("1️⃣ Checking for existing launchctl-managed Kanata service...")
let launchctlTask = Process()
launchctlTask.executableURL = URL(fileURLWithPath: "/usr/bin/launchctl")
launchctlTask.arguments = ["print", "system/com.keypath.kanata"]

let pipe = Pipe()
launchctlTask.standardOutput = pipe
launchctlTask.standardError = pipe

do {
    try launchctlTask.run()
    launchctlTask.waitUntilExit()

    if launchctlTask.terminationStatus == 0 {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        print("   ⚠️ Found existing launchctl-managed service")
        print("   Migration would need to:")
        print("     1. Detect launchctl service")
        print("     2. Unload via launchctl")
        print("     3. Remove plist from /Library/LaunchDaemons")
        print("     4. Register via SMAppService")
    } else {
        print("   ✅ No existing launchctl service (clean state)")
    }
} catch {
    print("   ℹ️ Could not check launchctl status: \(error)")
}

print("")

// Test 2: Check SMAppService status
print("2️⃣ Checking SMAppService status for helper...")
let svc = SMAppService.daemon(plistName: "com.keypath.helper.plist")
let status = svc.status

switch status {
case .enabled:
    print("   ⚠️ Helper already registered (could be via launchctl or SMAppService)")
    print("   Migration scenario: Need to detect which method was used")
case .notRegistered:
    print("   ✅ Not registered via SMAppService (clean state)")
case .requiresApproval:
    print("   ⚠️ Requires approval (pending user action)")
case .notFound:
    print("   ✅ Not found (clean state)")
@unknown default:
    print("   ⚠️ Unknown status: \(status.rawValue)")
}

print("")

// Test 3: Migration strategy
print("3️⃣ Migration Strategy Analysis:")
print("")
print("Key Challenges:")
print("  • Cannot distinguish SMAppService vs launchctl registration")
print("  • Both can result in .enabled status")
print("  • Need to check /Library/LaunchDaemons for legacy plist")
print("")
print("Recommended Migration Path:")
print("  1. Check for plist in /Library/LaunchDaemons/com.keypath.kanata.plist")
print("  2. If exists: Legacy launchctl installation detected")
print("  3. Unload via launchctl: sudo launchctl bootout system/com.keypath.kanata")
print("  4. Remove plist: sudo rm /Library/LaunchDaemons/com.keypath.kanata.plist")
print("  5. Register via SMAppService")
print("  6. Verify status transitions to .enabled")
print("")
print("Rollback Path:")
print("  1. Unregister via SMAppService")
print("  2. Reinstall via helper/launchctl")
print("  3. Verify service starts correctly")
print("")

// Test 4: Duplicate registration prevention
print("4️⃣ Duplicate Registration Prevention:")
print("")
print("Risk: Both SMAppService and launchctl could register same service")
print("")
print("Prevention Strategy:")
print("  • Always check for existing registration before migrating")
print("  • Unload launchctl service before SMAppService registration")
print("  • Verify only one registration method is active")
print("  • Log which method is being used")
print("")

print("✅ Migration/Rollback analysis complete")
print("")
