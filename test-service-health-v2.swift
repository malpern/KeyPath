#!/usr/bin/env swift

import Foundation

// Test the updated service health detection logic
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
    
    print("=== Updated Service Health Detection ===")
    print("Exit Code:", task.terminationStatus)
    
    if task.terminationStatus == 0 {
        print("Service is loaded. Checking health...")
        
        if output.contains("LastExitStatus") {
            print("Found property list format output")
            
            // Parse LastExitStatus
            if let lastExitMatch = output.range(of: "\"LastExitStatus\" = ([^;]+);", options: .regularExpression) {
                let lastExitStr = String(output[lastExitMatch]).replacingOccurrences(of: "\"LastExitStatus\" = ", with: "").replacingOccurrences(of: ";", with: "")
                let lastExitCode = Int(lastExitStr) ?? -999
                
                // Check if service has a PID (currently running)
                let hasPID = output.contains("\"PID\" =")
                
                print("Last Exit Code: \(lastExitCode)")
                print("Has PID (running): \(hasPID)")
                
                // Updated logic: service is healthy only if it has clean exit AND is running, or never ran
                let isHealthy = (lastExitCode == 0 && hasPID) || (!hasPID && lastExitCode == 0)
                
                print("Healthy: \(isHealthy)")
                
                if !isHealthy {
                    print("❌ Service is UNHEALTHY (exit code \(lastExitCode))")
                    print("   This will show 'LaunchDaemon Services Failing' in wizard")
                    print("   Fix action: 'Restart failing system services'")
                } else {
                    print("✅ Service is healthy")
                }
            } else {
                print("Could not parse LastExitStatus")
            }
        } else {
            print("No property list format found")
        }
    } else {
        print("❌ Service not loaded")
    }
    
} catch {
    print("Error: \(error)")
}