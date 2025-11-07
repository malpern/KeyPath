#!/usr/bin/env swift

import Foundation
import ServiceManagement
import OSLog

/// Simple standalone SMAppService test - validates concept without requiring app bundle
///
/// This tests SMAppService using the helper plist if available, or creates a test plist
/// that can be used once the app is built.
///
/// Usage:
///   swift dev-tools/debug/test-smappservice-simple.swift

let logger = Logger(subsystem: "com.keypath.debug", category: "SMAppServiceSimple")

print("🧪 Simple SMAppService POC Test")
print(String(repeating: "=", count: 50))
print()

guard #available(macOS 13, *) else {
    print("❌ SMAppService.daemon requires macOS 13+")
    exit(1)
}

// Test 1: Check if we can access SMAppService API
print("✅ SMAppService API available (macOS 13+)")
print()

// Test 2: Try to use helper plist if it exists in common locations
let possibleBundlePaths = [
    "dist/KeyPath.app",
    (NSString(string: "~/Applications/KeyPath.app")).expandingTildeInPath,
    "/Applications/KeyPath.app"
]

var foundBundle: String?
for path in possibleBundlePaths {
    if FileManager.default.fileExists(atPath: path) {
        foundBundle = path
        break
    }
}

if let bundlePath = foundBundle {
    print("✅ Found app bundle: \(bundlePath)")
    
    let helperPlistPath = "\(bundlePath)/Contents/Library/LaunchDaemons/com.keypath.helper.plist"
    if FileManager.default.fileExists(atPath: helperPlistPath) {
        print("✅ Found helper plist")
        print()
        print("📋 To test SMAppService with this plist, run:")
        print("   swift run smappservice-poc com.keypath.helper.plist lifecycle --verbose")
        print()
        print("   Note: This requires running from within the app bundle context.")
        print("   The 'swift run' command will handle this if the app is built.")
    } else {
        print("⚠️  Helper plist not found - app bundle may not be fully built")
    }
} else {
    print("⚠️  No app bundle found")
    print()
    print("💡 This test validates SMAppService concepts without requiring a build.")
    print("   Once you can build the app, you can test SMAppService with:")
    print("   swift run smappservice-poc com.keypath.helper.plist lifecycle --verbose")
}

print()
print("📝 Creating test plist for future use...")

let testPlistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.test-daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/echo</string>
        <string>Test daemon started</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/keypath-test-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/keypath-test-daemon.log</string>
</dict>
</plist>
"""

let testPlistPath = "./com.keypath.test-daemon.plist"
do {
    try testPlistContent.write(toFile: testPlistPath, atomically: true, encoding: .utf8)
    print("✅ Created test plist: \(testPlistPath)")
    
    // Validate plist
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
    task.arguments = ["-lint", testPlistPath]
    try task.run()
    task.waitUntilExit()
    
    if task.terminationStatus == 0 {
        print("✅ Plist is valid")
    }
} catch {
    print("⚠️  Could not create test plist: \(error)")
}

print()
print("📋 Summary:")
print("   • SMAppService API is available")
print("   • Test plist created: \(testPlistPath)")
print()
print("🚀 Next steps (once app can be built):")
print("   1. Copy test plist to app bundle:")
print("      cp \(testPlistPath) dist/KeyPath.app/Contents/Library/LaunchDaemons/")
print("   2. Test SMAppService:")
print("      swift run smappservice-poc com.keypath.test-daemon.plist lifecycle --verbose")
print()
print("   Or test with existing helper plist:")
print("      swift run smappservice-poc com.keypath.helper.plist lifecycle --verbose")

