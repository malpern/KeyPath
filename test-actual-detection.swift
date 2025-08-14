#!/usr/bin/env swift

import Foundation

// Test what the actual detection logic returns
print("🧪 Testing Actual Detection Logic")
print("=================================")

// Manually run the detection to see what ComponentDetector actually returns
class TestDetection {
    func runDetection() {
        print("📋 Simulating ComponentDetector.checkComponents()...")

        // 1. Check if plist exists (service loaded check)
        let plistPath = "/Library/LaunchDaemons/com.keypath.kanata.plist"
        let servicesLoaded = FileManager.default.fileExists(atPath: plistPath)
        print("✅ Services loaded: \(servicesLoaded)")

        // 2. Check if configuration is correct
        var kanataConfigured = false
        var vhidConfigured = true // Assume VHID is OK for this test

        if let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
           let args = dict["ProgramArguments"] as? [String] {
            let hasPort = args.contains("--port") && args.contains("5829")
            kanataConfigured = hasPort
            print("✅ Kanata configured correctly: \(kanataConfigured)")
            print("   Args: \(args)")
        } else {
            print("❌ Could not read plist")
        }

        // 3. Final decision (ComponentDetector logic)
        let launchDaemonServicesOK = servicesLoaded && kanataConfigured && vhidConfigured
        print("\n🎯 Final Result:")
        print("   Services loaded: \(servicesLoaded)")
        print("   Kanata configured: \(kanataConfigured)")
        print("   VHID configured: \(vhidConfigured)")
        print("   LaunchDaemon services marked as installed: \(launchDaemonServicesOK)")

        if launchDaemonServicesOK {
            print("\n🚨 PROBLEM: Services marked as installed when they shouldn't be!")
            print("   This explains why wizard shows all green.")
        } else {
            print("\n✅ CORRECT: Services correctly marked as needing attention.")
            print("   Wizard should show issues.")
        }
    }
}

let test = TestDetection()
test.runDetection()
