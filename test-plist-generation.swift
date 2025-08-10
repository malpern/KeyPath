#!/usr/bin/swift

import Foundation

// Test path resolution
let userConfigPath = "\(NSHomeDirectory())/.config/keypath/keypath.kbd"
print("User config path: \(userConfigPath)")

// Test that file exists
if FileManager.default.fileExists(atPath: userConfigPath) {
    print("✅ Config file exists at new location")
} else {
    print("❌ Config file missing at new location")
}

// Show what the plist would contain
let mockPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.kanata</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kanata</string>
        <string>--cfg</string>
        <string>\(userConfigPath)</string>
        <string>--watch</string>
        <string>--debug</string>
        <string>--log-layer-changes</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
"""

print("\n📋 Generated plist would contain:")
print(mockPlist)