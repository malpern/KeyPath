#!/usr/bin/swift

import Foundation

print("🔄 Restarting Kanata service to apply updated --watch flags...")

// Use launchctl kickstart which should reload the service with new plist
let script = """
do shell script "launchctl kickstart -k system/com.keypath.kanata" with administrator privileges with prompt "KeyPath needs to restart the Kanata service to apply --watch flag for hot reloading."
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
        print("✅ Service restart command executed")
        
        // Wait for service to restart
        sleep(3)
        
        // Check the new process arguments
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        checkTask.arguments = ["print", "system/com.keypath.kanata"]
        
        let checkPipe = Pipe()
        checkTask.standardOutput = checkPipe
        
        try checkTask.run()
        checkTask.waitUntilExit()
        
        let checkData = checkPipe.fileHandleForReading.readDataToEndOfFile()
        let checkOutput = String(data: checkData, encoding: .utf8) ?? ""
        
        // Extract and show the arguments section
        if let argsStart = checkOutput.range(of: "arguments = {")?.upperBound,
           let argsEnd = checkOutput.range(of: "}", range: argsStart..<checkOutput.endIndex)?.lowerBound {
            let argsSection = String(checkOutput[argsStart..<argsEnd])
            print("\n📋 Current service arguments:")
            print(argsSection)
            
            if argsSection.contains("--watch") {
                print("\n✅ SUCCESS: Service is now running with --watch flag!")
                print("🔍 Hot reloading should work when you modify keyboard mappings")
            } else {
                print("\n⚠️ Service restarted but --watch flag not detected")
            }
        }
        
    } else {
        print("❌ Failed to restart service: \(output)")
    }
} catch {
    print("❌ Error: \(error)")
}