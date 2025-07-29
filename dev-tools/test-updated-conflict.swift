#!/usr/bin/swift

import Foundation

func testUpdatedConflictDetection() -> (hasConflicts: Bool, conflictDescription: String?) {
    print("🔍 [Test] Testing updated conflict detection...")
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-fl", "kanata-cmd"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        print("🔍 [Test] pgrep output: '\(output)'")
        
        if output.isEmpty {
            print("🔍 [Test] ✅ No Kanata processes found")
            return (false, nil)
        }
        
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        print("🔍 [Test] Found \(lines.count) process(es)")
        
        // For each PID, check if it's running as root
        var rootProcessCount = 0
        var totalProcessCount = 0
        
        for line in lines {
            print("🔍 [Test] Process: \(line)")
            let components = line.components(separatedBy: " ")
            if let pid = components.first {
                totalProcessCount += 1
                
                // Use ps to check the user for this specific PID
                let psTask = Process()
                psTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                psTask.arguments = ["-p", pid, "-o", "user="]
                
                let psPipe = Pipe()
                psTask.standardOutput = psPipe
                
                do {
                    try psTask.run()
                    psTask.waitUntilExit()
                    
                    let userData = psPipe.fileHandleForReading.readDataToEndOfFile()
                    let user = String(data: userData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    print("🔍 [Test] PID \(pid) runs as user: '\(user)'")
                    
                    if user == "root" {
                        rootProcessCount += 1
                    }
                } catch {
                    print("🔍 [Test] Failed to check user for PID \(pid): \(error)")
                }
            }
        }
        
        if rootProcessCount > 0 {
            let message = "Found \(rootProcessCount) Kanata process(es) running as root that need to be terminated before KeyPath can manage its own Kanata instance."
            print("🔍 [Test] ❌ CONFLICTS DETECTED: \(message)")
            return (true, message)
        } else if totalProcessCount > 0 {
            let message = "Found \(totalProcessCount) existing Kanata process(es) that need to be terminated before KeyPath can manage its own instance."
            print("🔍 [Test] ❌ CONFLICTS DETECTED: \(message)")
            return (true, message)
        }
        
        print("🔍 [Test] ✅ No conflicting Kanata processes found")
        return (false, nil)
        
    } catch {
        print("🔍 [Test] pgrep failed: \(error)")
        return (false, nil)
    }
}

// Test the function
let result = testUpdatedConflictDetection()
print("🔍 [Test] FINAL RESULT: hasConflicts=\(result.hasConflicts), description=\(result.conflictDescription ?? "none")")