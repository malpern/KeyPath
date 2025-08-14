#!/usr/bin/env swift

import Foundation

// Test TCP preferences and plist generation
print("🔧 Testing TCP server preferences and plist generation...")

// Simulate preferences being set
UserDefaults.standard.set(true, forKey: "KeyPath.TCP.ServerEnabled")
UserDefaults.standard.set(37000, forKey: "KeyPath.TCP.ServerPort")

// Create a snapshot like the LaunchDaemon installer would
let enabled = UserDefaults.standard.object(forKey: "KeyPath.TCP.ServerEnabled") as? Bool ?? true
let port = UserDefaults.standard.object(forKey: "KeyPath.TCP.ServerPort") as? Int ?? 37000

print("✅ TCP enabled: \(enabled)")
print("✅ TCP port: \(port)")

// Test the logic that would be used in buildKanataPlistArguments
var arguments = ["/usr/local/bin/kanata", "--cfg", "/Users/malpern/.config/keypath/keypath.kbd"]

if enabled && port > 1024 && port < 65536 {
    arguments.append("--port")
    arguments.append(String(port))
    print("✅ TCP arguments added: \(arguments.suffix(2))")
} else {
    print("❌ TCP not added - enabled: \(enabled), port: \(port)")
}

arguments.append("--watch")
arguments.append("--debug")
arguments.append("--log-layer-changes")

print("🔧 Full kanata command arguments:")
print("   \(arguments.joined(separator: " "))")

print("\n🔧 Expected plist XML arguments section:")
for arg in arguments {
    print("                <string>\(arg)</string>")
}