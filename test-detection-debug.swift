#!/usr/bin/env swift

import Foundation

// Debug the detection logic to see why wizard shows all green
print("🐛 Debugging Wizard Detection Logic")
print("===================================")

// Simulate the ComponentDetector logic
class TestLaunchDaemonInstaller {
    static let kanataServiceID = "com.keypath.kanata"
    static let launchDaemonsPath = "/Library/LaunchDaemons"

    func getServiceStatus() -> Bool {
        // Check if plist file exists (this is what isServiceLoaded likely checks)
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        let exists = FileManager.default.fileExists(atPath: plistPath)
        print("📁 Service plist exists: \(exists)")
        return exists // Simplified - just checking one service
    }

    func isKanataServiceConfiguredCorrectly() -> Bool {
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        print("🔍 Checking configuration at: \(plistPath)")

        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            print("❌ Could not read plist")
            return false
        }

        guard let args = dict["ProgramArguments"] as? [String] else {
            print("❌ No ProgramArguments found")
            return false
        }

        let hasPortFlag = args.contains("--port")
        let hasPortValue = args.contains("5829")

        print("📋 Current args: \(args)")
        print("🔍 Has --port flag: \(hasPortFlag)")
        print("🔍 Has 5829 value: \(hasPortValue)")

        return hasPortFlag && hasPortValue
    }
}

let installer = TestLaunchDaemonInstaller()

print("\n1️⃣ Testing service status check...")
let status = installer.getServiceStatus()
print("   Services loaded: \(status)")

print("\n2️⃣ Testing configuration validation...")
let configCorrect = installer.isKanataServiceConfiguredCorrectly()
print("   Configuration correct: \(configCorrect)")

print("\n3️⃣ Combined result (ComponentDetector logic)...")
let shouldBeInstalled = status && configCorrect
print("   LaunchDaemon services should be marked as 'installed': \(shouldBeInstalled)")
print("   Expected: false (because config is missing --port)")

if shouldBeInstalled {
    print("\n🚨 BUG FOUND: Services are incorrectly marked as installed!")
    print("   This explains why wizard shows all green.")
} else {
    print("\n✅ Detection logic is working correctly!")
    print("   Wizard should show LaunchDaemon services need fixing.")
}
