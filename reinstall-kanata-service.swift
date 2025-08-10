#!/usr/bin/swift

import Foundation

// Simple script to reinstall Kanata LaunchDaemon service with correct flags
print("🔧 Reinstalling Kanata LaunchDaemon service with --watch, --debug, --log-layer-changes flags")

// Path to the LaunchDaemon plist
let serviceID = "com.keypath.kanata"
let plistPath = "/Library/LaunchDaemons/\(serviceID).plist"

// First, try to unload the existing service
print("📤 Unloading existing service...")
let unloadTask = Process()
unloadTask.launchPath = "/bin/launchctl"
unloadTask.arguments = ["unload", plistPath]

do {
    try unloadTask.run()
    unloadTask.waitUntilExit()
    if unloadTask.terminationStatus == 0 {
        print("✅ Successfully unloaded existing service")
    } else {
        print("⚠️ Service may not have been loaded (this is OK)")
    }
} catch {
    print("⚠️ Could not unload service: \(error)")
}

// Generate the corrected plist content
let kanataBinaryPath = "/usr/local/bin/kanata"
let configPath = "/usr/local/etc/kanata/keypath.kbd"

let plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(serviceID)</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(kanataBinaryPath)</string>
        <string>--cfg</string>
        <string>\(configPath)</string>
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
</dict>
</plist>
"""

// Write to temporary file
let tempPath = NSTemporaryDirectory() + "\(serviceID).plist"
do {
    try plistContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
    print("📝 Created temporary plist at: \(tempPath)")
} catch {
    print("❌ Failed to create temporary plist: \(error)")
    exit(1)
}

// Copy to system location with admin privileges
print("🔐 Requesting admin privileges to install corrected LaunchDaemon...")
let copyCommand = "cp '\(tempPath)' '\(plistPath)' && chmod 644 '\(plistPath)' && chown root:wheel '\(plistPath)'"

let script = """
do shell script "\(copyCommand)" with administrator privileges with prompt "KeyPath needs to reinstall the Kanata LaunchDaemon with corrected --watch flags."
"""

let appleScript = NSAppleScript(source: script)
var error: NSDictionary?
appleScript?.executeAndReturnError(&error)

if let error = error {
    print("❌ Failed to install plist: \(error)")
    exit(1)
}

print("✅ Successfully installed corrected plist")

// Load the new service
print("🚀 Loading corrected service...")
let loadTask = Process()
loadTask.launchPath = "/bin/launchctl"
loadTask.arguments = ["load", plistPath]

do {
    try loadTask.run()
    loadTask.waitUntilExit()
    
    if loadTask.terminationStatus == 0 {
        print("✅ Successfully loaded Kanata service with --watch, --debug, --log-layer-changes flags")
        print("🔍 You should now see hot reloading working when you change keyboard mappings")
        
        // Show the running process
        sleep(2)
        let psTask = Process()
        psTask.launchPath = "/bin/ps"
        psTask.arguments = ["aux"]
        
        let pipe = Pipe()
        psTask.standardOutput = pipe
        
        try psTask.run()
        psTask.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        let kanataLines = output.components(separatedBy: .newlines).filter { $0.contains("kanata") && !$0.contains("grep") }
        if !kanataLines.isEmpty {
            print("\n📊 Kanata process status:")
            for line in kanataLines {
                print("   \(line)")
            }
        }
        
    } else {
        print("❌ Failed to load service")
        exit(1)
    }
} catch {
    print("❌ Error loading service: \(error)")
    exit(1)
}