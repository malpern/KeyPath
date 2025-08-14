#!/usr/bin/env swift

import Foundation

print("🔧 Testing LaunchDaemon service installation...")

// Simulate the exact plist generation that LaunchDaemonInstaller would create
let kanataBinaryPath = "/usr/local/bin/kanata"
let configPath = "/Users/malpern/.config/keypath/keypath.kbd"

// Build arguments like LaunchDaemonInstaller.buildKanataPlistArguments
var arguments = [kanataBinaryPath, "--cfg", configPath]

// Add TCP port (this is what we want to test)
let tcpEnabled = true
let tcpPort = 37000

if tcpEnabled {
    arguments.append("--port")
    arguments.append(String(tcpPort))
}

arguments.append("--watch")
arguments.append("--debug")
arguments.append("--log-layer-changes")

print("✅ Arguments: \(arguments.joined(separator: " "))")

// Generate the plist content (simplified version)
var argumentsXML = ""
for arg in arguments {
    argumentsXML += "        <string>\(arg)</string>\n"
}

let plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keypath.kanata</string>
    <key>Program</key>
    <string>\(kanataBinaryPath)</string>
    <key>ProgramArguments</key>
    <array>
\(argumentsXML)    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/kanata.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/kanata.log</string>
</dict>
</plist>
"""

print("\n🔧 Generated plist content:")
print("✅ Includes --port \(tcpPort): \(arguments.contains("--port"))")
print("✅ Plist length: \(plistContent.count) characters")

// Test if we can write to temp directory
let tempPath = "/tmp/test-kanata-service.plist"
do {
    try plistContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
    print("✅ Successfully wrote plist to \(tempPath)")
    
    // Show first few lines
    let content = try String(contentsOfFile: tempPath)
    let lines = content.components(separatedBy: "\n").prefix(15)
    print("\n🔍 First 15 lines of generated plist:")
    for line in lines {
        print("  \(line)")
    }
    
    // Clean up
    try FileManager.default.removeItem(atPath: tempPath)
    print("\n✅ Cleanup completed")
    
} catch {
    print("❌ Failed to write plist: \(error)")
}

print("\n🔧 This plist should be installed to:")
print("  /Library/LaunchDaemons/com.keypath.kanata.plist")