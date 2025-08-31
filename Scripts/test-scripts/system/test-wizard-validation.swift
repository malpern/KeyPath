#!/usr/bin/env swift

import Foundation

// Test script to validate the wizard's new detection logic
print("🧪 Testing Wizard Validation Logic")
print("==================================")

// Test the new LaunchDaemon validation
@_silgen_name("swift_retainCount")
func swift_retainCount(_: AnyObject) -> UInt

class LaunchDaemonInstaller {
    static let kanataServiceID = "com.keypath.kanata"
    static let launchDaemonsPath = "/Library/LaunchDaemons"

    func isKanataServiceConfiguredCorrectly() -> Bool {
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        print("📋 Checking plist at: \(plistPath)")

        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            print("❌ Plist not found or unreadable")
            return false
        }

        guard let args = dict["ProgramArguments"] as? [String] else {
            print("❌ ProgramArguments missing or malformed")
            return false
        }

        print("📝 Current ProgramArguments:")
        for (index, arg) in args.enumerated() {
            print("  [\(index)] \(arg)")
        }

        // Check for required arguments
        let hasPortFlag = args.contains("--port")
        let hasPortValue = args.contains("5829")

        print("\n🔍 Validation Results:")
        print("  - Port flag (--port): \(hasPortFlag)")
        print("  - Port value (5829): \(hasPortValue)")

        let isCorrect = hasPortFlag && hasPortValue
        print("  - Overall result: \(isCorrect ? "✅ CORRECT" : "❌ NEEDS UPDATE")")

        return isCorrect
    }
}

let installer = LaunchDaemonInstaller()
let result = installer.isKanataServiceConfiguredCorrectly()

print("\n🎯 Test Result: \(result ? "PASS" : "FAIL")")
print("Expected: FAIL (because current plist doesn't have TCP server config)")
print("If wizard detects this correctly, it should show LaunchDaemon services as needing attention.")
