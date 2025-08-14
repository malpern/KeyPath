#!/usr/bin/swift

import Foundation

print("🔄 Updating Kanata service to use ~/.config/keypath/keypath.kbd...")

let serviceID = "com.keypath.kanata"
let newConfigPath = "/Users/malpern/.config/keypath/keypath.kbd"

// Create new plist content
let plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(serviceID)</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kanata</string>
        <string>--cfg</string>
        <string>\(newConfigPath)</string>
        <string>--watch</string>
        <string>--debug</string>
        <string>--log-layer-changes</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/kanata.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/kanata.log</string>
    <key>UserName</key>
    <string>root</string>
    <key>GroupName</key>
    <string>wheel</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
"""

// Write to temporary file
let tempPath = NSTemporaryDirectory() + "com.keypath.kanata.plist"
do {
    try plistContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
    print("📝 Created temporary plist at: \(tempPath)")
} catch {
    print("❌ Failed to create temporary plist: \(error)")
    exit(1)
}

// Simple command to stop, replace, and start service
let command = "launchctl bootout system/\(serviceID) 2>/dev/null || echo 'Service not loaded'; cp '\(tempPath)' '/Library/LaunchDaemons/\(serviceID).plist'; chown root:wheel '/Library/LaunchDaemons/\(serviceID).plist'; chmod 644 '/Library/LaunchDaemons/\(serviceID).plist'; launchctl bootstrap system '/Library/LaunchDaemons/\(serviceID).plist'"

let osascriptCommand = "do shell script \"\(command)\" with administrator privileges with prompt \"Update Kanata to use ~/.config/keypath path\""

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-e", osascriptCommand]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    if task.terminationStatus == 0 {
        print("✅ Service updated successfully!")
        print("Output: \(output)")
    } else {
        print("❌ Failed to update: \(output)")
    }
} catch {
    print("❌ Error: \(error)")
}
