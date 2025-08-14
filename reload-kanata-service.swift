#!/usr/bin/swift

import Foundation

print("🔄 Reloading Kanata service to pick up updated plist with --watch flags...")

let serviceID = "com.keypath.kanata"
let plistPath = "/Library/LaunchDaemons/\(serviceID).plist"

// Use osascript to reload the service with admin privileges
let script = """
do shell script "launchctl bootout system/\(serviceID) && launchctl bootstrap system \(plistPath)" with administrator privileges with prompt "KeyPath needs to reload the Kanata service to apply updated configuration flags."
"""

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-e", script]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    if task.terminationStatus == 0 {
        print("✅ Successfully reloaded Kanata service")

        // Wait a moment then check the service
        sleep(2)

        // Check if service is running with correct flags
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        checkTask.arguments = ["print", "system/\(serviceID)"]

        let checkPipe = Pipe()
        checkTask.standardOutput = checkPipe

        try checkTask.run()
        checkTask.waitUntilExit()

        let checkData = checkPipe.fileHandleForReading.readDataToEndOfFile()
        let checkOutput = String(data: checkData, encoding: .utf8) ?? ""

        if checkOutput.contains("--watch") && checkOutput.contains("--debug") {
            print("✅ Service is now running with correct flags including --watch")
            print("🔍 Hot reloading should now work when you modify keyboard mappings")
        } else {
            print("⚠️ Service reloaded but flags may not be applied correctly")
        }

    } else {
        print("❌ Failed to reload service: \(output)")
    }
} catch {
    print("❌ Error reloading service: \(error)")
}
