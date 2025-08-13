#!/usr/bin/env swift

import Foundation

// Check what's actually in the LaunchDaemon plist
let plistPath = "/Library/LaunchDaemons/com.keypath.kanata.plist"

print("Checking LaunchDaemon plist at: \(plistPath)")

do {
    let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
    if let plistDict = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
        print("\nPlist contents:")
        if let programArguments = plistDict["ProgramArguments"] as? [String] {
            print("ProgramArguments:")
            for (index, arg) in programArguments.enumerated() {
                print("  [\(index)] \(arg)")
            }
            
            if programArguments.contains("--port") {
                print("\n✅ TCP server flag found!")
            } else {
                print("\n❌ TCP server flag missing!")
            }
        } else {
            print("No ProgramArguments found")
        }
    }
} catch {
    print("Error reading plist: \(error)")
}