#!/usr/bin/swift

import Foundation

let userConfigPath = "/Users/malpern/Library/Application Support/KeyPath/keypath.kbd"
let systemConfigPath = "/usr/local/etc/kanata/keypath.kbd"

print("🔄 Testing config synchronization from user to system path...")
print("User config: \(userConfigPath)")
print("System config: \(systemConfigPath)")

// Read user config
guard let userConfig = try? String(contentsOfFile: userConfigPath) else {
    print("❌ Could not read user config")
    exit(1)
}

print("📖 User config content:")
print(userConfig)

// Use AppleScript to copy with admin privileges
let script = """
do shell script "cp '\(userConfigPath)' '\(systemConfigPath)'" with administrator privileges with prompt "Test config sync for hot reload verification"
"""

let appleScript = NSAppleScript(source: script)
var error: NSDictionary?
appleScript?.executeAndReturnError(&error)

if let error {
    print("❌ Failed to sync config: \(error)")
} else {
    print("✅ Config synchronized to system path")
    print("🔍 Kanata should now detect the change and reload...")
}
