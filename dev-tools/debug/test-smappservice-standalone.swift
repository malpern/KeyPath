#!/usr/bin/env swift

import Foundation
import ServiceManagement
import OSLog

/// Standalone SMAppService POC test - works with existing app bundle or creates minimal test
///
/// This script tests SMAppService registration/unregistration. It can:
/// 1. Use an existing built app bundle (dist/KeyPath.app or ~/Applications/KeyPath.app)
/// 2. Test with the helper plist that should already exist
///
/// Usage:
///   swift dev-tools/debug/test-smappservice-standalone.swift
///   swift dev-tools/debug/test-smappservice-standalone.swift --use-dist
///   swift dev-tools/debug/test-smappservice-standalone.swift --create-test-plist

let logger = Logger(subsystem: "com.keypath.debug", category: "SMAppServiceStandalone")

print("🧪 SMAppService Standalone POC Test")
print(String(repeating: "=", count: 50))
print()

guard #available(macOS 13, *) else {
    print("❌ SMAppService.daemon requires macOS 13+")
    print("   Current version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    exit(1)
}

let args = CommandLine.arguments
let useDist = args.contains("--use-dist")
let createTestPlist = args.contains("--create-test-plist")

// Find existing app bundle
var appBundlePath: String?
let possiblePaths = [
    "dist/KeyPath.app",
    "~/Applications/KeyPath.app",
    "/Applications/KeyPath.app"
]

if useDist {
    appBundlePath = FileManager.default.fileExists(atPath: "dist/KeyPath.app") ? "dist/KeyPath.app" : nil
} else {
    for path in possiblePaths {
        let expandedPath = (path as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            appBundlePath = expandedPath
            break
        }
    }
}

if let bundlePath = appBundlePath {
    print("✅ Found app bundle: \(bundlePath)")

    // Check for helper plist
    let helperPlistPath = "\(bundlePath)/Contents/Library/LaunchDaemons/com.keypath.helper.plist"
    if FileManager.default.fileExists(atPath: helperPlistPath) {
        print("✅ Found helper plist: \(helperPlistPath)")
        print()
        print("📋 Testing SMAppService with existing helper plist...")
        print("   Note: This requires running from within the app bundle context.")
        print("   Use: swift run smappservice-poc com.keypath.helper.plist lifecycle --verbose")
        print()
    } else {
        print("⚠️  Helper plist not found at: \(helperPlistPath)")
        print("   The app bundle may not be fully built.")
    }
} else {
    print("⚠️  No app bundle found at expected locations:")
    for path in possiblePaths {
        print("   - \(path)")
    }
    print()
}

// Create test plist if requested
if createTestPlist {
    print("📝 Creating test daemon plist...")

    let testPlistName = "com.keypath.test-daemon.plist"
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

    // Try to write to existing app bundle, or create standalone
    if let bundlePath = appBundlePath {
        let launchDaemonsPath = "\(bundlePath)/Contents/Library/LaunchDaemons"
        let testPlistPath = "\(launchDaemonsPath)/\(testPlistName)"

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: launchDaemonsPath) {
            try? FileManager.default.createDirectory(atPath: launchDaemonsPath, withIntermediateDirectories: true)
        }

        do {
            try testPlistContent.write(toFile: testPlistPath, atomically: true, encoding: .utf8)
            print("✅ Created test plist: \(testPlistPath)")

            // Validate
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            task.arguments = ["-lint", testPlistPath]
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                print("✅ Plist is valid")
                print()
                print("📋 Next steps:")
                print("   1. Rebuild app bundle to include this plist")
                print("   2. Run: swift run smappservice-poc \(testPlistName) lifecycle --verbose")
            }
        } catch {
            print("❌ Failed to create test plist: \(error)")
        }
    } else {
        // Create standalone test plist
        let standalonePath = "./\(testPlistName)"
        do {
            try testPlistContent.write(toFile: standalonePath, atomically: true, encoding: .utf8)
            print("✅ Created standalone test plist: \(standalonePath)")
            print("   Copy this to your app bundle's Contents/Library/LaunchDaemons/ when ready")
        } catch {
            print("❌ Failed to create test plist: \(error)")
        }
    }
} else {
    print("💡 Usage:")
    print("   swift dev-tools/debug/test-smappservice-standalone.swift --create-test-plist")
    print("   swift dev-tools/debug/test-smappservice-standalone.swift --use-dist")
    print()
    print("📋 Alternative: Test with existing helper plist (if app is built):")
    print("   swift run smappservice-poc com.keypath.helper.plist lifecycle --verbose")
}

