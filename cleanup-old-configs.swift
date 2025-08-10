#!/usr/bin/swift

import Foundation

print("🧹 Cleaning up old Kanata config files...")

// Remove old system config files with admin privileges
let script = "rm -f '/usr/local/etc/kanata/keypath.kbd' && rmdir '/usr/local/etc/kanata' 2>/dev/null || echo 'System config cleanup completed'"

let osascriptCommand = "do shell script \"\(script)\" with administrator privileges with prompt \"KeyPath needs to clean up old system configuration files before switching to ~/.config/ location.\""

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
        print("✅ Old system config files cleaned up")
        print("Output: \(output)")
    } else {
        print("⚠️ System config cleanup had issues: \(output)")
    }
} catch {
    print("❌ Error during cleanup: \(error)")
}

print("🎯 Ready to switch to ~/.config/keypath/keypath.kbd")