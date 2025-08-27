#!/usr/bin/env swift

import Foundation

// Simple test to verify service health detection
let task = Process()
task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
task.arguments = ["list", "com.keypath.kanata"]

let pipe = Pipe()
task.standardOutput = pipe
task.standardError = pipe

do {
    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    print("=== Kanata Service Status ===")
    print("Exit Code:", task.terminationStatus)
    print("Raw Output:")
    print(output)
    print("===========================")

    if task.terminationStatus == 0 {
        let lines = output.components(separatedBy: .newlines)
        for line in lines.dropFirst() { // Skip header
            if line.contains("com.keypath.kanata") {
                let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if components.count >= 3 {
                    let pidStr = components[0]
                    let exitCodeStr = components[1]
                    let serviceID = components[2]

                    print("PID: '\(pidStr)'")
                    print("Exit Code: '\(exitCodeStr)'")
                    print("Service ID: '\(serviceID)'")

                    let isHealthy = (pidStr == "-" && (exitCodeStr == "0" || exitCodeStr == "-")) ||
                        (Int(pidStr) ?? -1 > 0 && exitCodeStr == "0")

                    print("Healthy: \(isHealthy)")

                    if !isHealthy {
                        print("❌ Service is UNHEALTHY - should show as red in wizard")
                        print("   This should trigger the 'Restart failing system services' fix")
                    } else {
                        print("✅ Service is healthy")
                    }
                }
            }
        }
    } else {
        print("❌ Service not loaded")
    }

} catch {
    print("Error: \(error)")
}
