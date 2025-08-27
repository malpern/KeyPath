#!/usr/bin/env swift

import ApplicationServices
import Foundation
import IOKit.hid

print("🔮 ORACLE SYSTEM TEST")
print(String(repeating: "=", count: 60))
print()

print("📋 Testing the new PermissionOracle system that replaces")
print("   the chaotic permission detection with authoritative checks.")
print()

// Test 1: KeyPath Local Permissions (Apple APIs)
print("🔍 Test 1: KeyPath Permission Detection")
print(String(repeating: "-", count: 40))

let axGranted = AXIsProcessTrusted()
print("   Accessibility (AXIsProcessTrusted): \(axGranted ? "✅ GRANTED" : "❌ DENIED")")

let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
let imGranted = accessType == kIOHIDAccessTypeGranted
print("   Input Monitoring (IOHIDCheckAccess): \(imGranted ? "✅ GRANTED" : "❌ DENIED")")
print("   Raw IOHIDCheckAccess result: \(accessType)")
print()

// Test 2: TCP Server Availability
print("🌐 Test 2: Kanata TCP Server Detection")
print(String(repeating: "-", count: 40))

let tcpPorts = [1111, 5829, 37000, 37001] // Common Kanata TCP ports

for port in tcpPorts {
    let result = testTCPConnection(host: "127.0.0.1", port: port, timeout: 1.0)
    let status = result ? "🟢 AVAILABLE" : "🔴 UNAVAILABLE"
    print("   Port \(port): \(status)")
}

print()

// Test 3: Full Disk Access Detection
print("📂 Test 3: Full Disk Access (TCC Fallback)")
print(String(repeating: "-", count: 40))

let tccPath = NSHomeDirectory().appending("/Library/Application Support/com.apple.TCC/TCC.db")
let hasFDA = FileManager.default.isReadableFile(atPath: tccPath)
print("   TCC Database Access: \(hasFDA ? "✅ AVAILABLE" : "❌ DENIED")")
print("   Path: \(tccPath)")
print()

// Test 4: Kanata Binary Detection
print("🔧 Test 4: Kanata Binary Detection")
print(String(repeating: "-", count: 40))

let possiblePaths = [
    "/opt/homebrew/bin/kanata",
    "/usr/local/bin/kanata",
    "/usr/bin/kanata"
]

var kanataFound = false
for path in possiblePaths {
    if FileManager.default.isExecutableFile(atPath: path) {
        print("   ✅ Found: \(path)")
        kanataFound = true
    } else {
        print("   ❌ Not found: \(path)")
    }
}

if !kanataFound {
    print("   ⚠️  No Kanata binary found - TCP permission check will be only source")
}

print()

// Test 5: Oracle Expected Behavior Summary
print("🔮 Oracle System Behavior Summary")
print(String(repeating: "-", count: 40))

print("   PERMISSION DETECTION HIERARCHY:")
print("   1. 🥇 Kanata TCP API (authoritative when available)")
print("   2. 🥈 Apple APIs for KeyPath (AXIsProcessTrusted, IOHIDCheckAccess)")
print("   3. 🥉 TCC Database (fallback when Full Disk Access available)")
print("   4. ❓ Unknown (never guess from logs or patterns)")
print()

print("   WHAT'S ELIMINATED:")
print("   ❌ Log parsing and error pattern matching")
print("   ❌ CGEvent tap testing (unreliable)")
print("   ❌ Conflicting results from multiple sources")
print("   ❌ Binary path confusion")
print()

print("   EXPECTED RESULTS:")
if axGranted, imGranted {
    print("   ✅ KeyPath permissions: READY")
} else {
    print("   ⚠️  KeyPath permissions: NEEDS ATTENTION")
    if !axGranted {
        print("       - Grant Accessibility in System Settings")
    }
    if !imGranted {
        print("       - Grant Input Monitoring in System Settings")
    }
}

print()
print("🚀 To test Oracle in KeyPath:")
print("   1. Open KeyPath.app from Applications")
print("   2. Check Console.app for Oracle logs (search for '🔮 [Oracle]')")
print("   3. Watch for permission detection behavior changes")
print("   4. Test permission changes in System Settings")
print()

print("📝 Oracle should provide:")
print("   • Sub-2-second permission checks")
print("   • Clear source attribution (TCP/APIs/TCC)")
print("   • Consistent results for same conditions")
print("   • Actionable error messages")
print()

// Helper function for TCP testing
func testTCPConnection(host: String, port: Int, timeout _: TimeInterval) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    task.arguments = ["-z", "-w", "1", host, String(port)]
    task.standardOutput = Pipe()
    task.standardError = Pipe()

    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return false
    }
}
