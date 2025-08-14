#!/usr/bin/swift

import Foundation

print("🔄 Completely reloading Kanata service with updated plist...")

let serviceID = "com.keypath.kanata"
let plistPath = "/Library/LaunchDaemons/\(serviceID).plist"

// Use bootout + bootstrap to completely reload the service
let script = """
do shell script "launchctl bootout system/\(serviceID); sleep 1; launchctl bootstrap system \(plistPath)" with administrator privileges with prompt "KeyPath needs to reload the Kanata service configuration to enable hot reloading."
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

    print("Command output: \(output)")

    // Wait for service to fully restart
    print("⏳ Waiting for service to restart...")
    sleep(5)

    // Check the service status
    let checkTask = Process()
    checkTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    checkTask.arguments = ["print", "system/\(serviceID)"]

    let checkPipe = Pipe()
    checkTask.standardOutput = checkPipe

    try checkTask.run()
    checkTask.waitUntilExit()

    if checkTask.terminationStatus == 0 {
        let checkData = checkPipe.fileHandleForReading.readDataToEndOfFile()
        let checkOutput = String(data: checkData, encoding: .utf8) ?? ""

        // Look for the arguments section
        let lines = checkOutput.components(separatedBy: .newlines)
        var inArgsSection = false
        var foundWatch = false

        print("\n📋 Service arguments:")
        for line in lines {
            if line.contains("arguments = {") {
                inArgsSection = true
                continue
            }
            if inArgsSection {
                if line.contains("}") {
                    break
                }
                print("  \(line.trimmingCharacters(in: .whitespaces))")
                if line.contains("--watch") {
                    foundWatch = true
                }
            }
        }

        if foundWatch {
            print("\n✅ SUCCESS: Kanata service is now running with --watch flag!")
            print("🔥 Hot reloading should work when you modify keyboard mappings")
        } else {
            print("\n❌ FAILED: --watch flag still not found in running service")
            print("The plist may not have been reloaded properly.")
        }

        // Also check the actual running process
        let psTask = Process()
        psTask.executableURL = URL(fileURLWithPath: "/bin/ps")
        psTask.arguments = ["aux"]

        let psPipe = Pipe()
        psTask.standardOutput = psPipe

        try psTask.run()
        psTask.waitUntilExit()

        let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
        let psOutput = String(data: psData, encoding: .utf8) ?? ""

        let kanataLines = psOutput.components(separatedBy: .newlines).filter {
            $0.contains("kanata") && !$0.contains("grep") && $0.contains("/usr/local/bin/kanata")
        }

        if !kanataLines.isEmpty {
            print("\n🔍 Running Kanata process:")
            for line in kanataLines {
                print("  \(line)")
                if line.contains("--watch") {
                    print("  ✅ Process shows --watch flag!")
                }
            }
        }

    } else {
        print("❌ Service may not be running properly")
    }

} catch {
    print("❌ Error: \(error)")
}
