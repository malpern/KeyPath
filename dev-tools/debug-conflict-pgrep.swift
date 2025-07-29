#!/usr/bin/swift

import Foundation

func testPgrepApproach() -> (hasConflicts: Bool, conflictDescription: String?) {
    print("🔍 [Debug] Testing pgrep approach...")
    
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
        
        print("🔍 [Debug] pgrep output: '\(output)'")
        
        if output.isEmpty {
            print("🔍 [Debug] No Kanata processes found")
            return (false, nil)
        }
        
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        print("🔍 [Debug] Found \(lines.count) process(es)")
        
        for line in lines {
            print("🔍 [Debug] Process: \(line)")
        }
        
        // For each PID, check if it's running as root
        var rootProcessCount = 0
        for line in lines {
            let components = line.components(separatedBy: " ")
            if let pid = components.first {
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
                    
                    print("🔍 [Debug] PID \(pid) runs as user: '\(user)'")
                    
                    if user == "root" {
                        rootProcessCount += 1
                    }
                } catch {
                    print("🔍 [Debug] Failed to check user for PID \(pid): \(error)")
                }
            }
        }
        
        if rootProcessCount > 0 {
            return (true, "Found \(rootProcessCount) Kanata process(es) running as root that need to be terminated before KeyPath can manage its own Kanata instance.")
        } else if lines.count > 0 {
            return (true, "Found \(lines.count) existing Kanata process(es) that need to be terminated before KeyPath can manage its own instance.")
        }
        
        return (false, nil)
        
    } catch {
        print("🔍 [Debug] pgrep failed: \(error)")
        return (false, nil)
    }
}

// Test both approaches
print("=== Testing pgrep approach ===")
let pgrepResult = testPgrepApproach()
print("🔍 [Debug] pgrep result: hasConflicts=\(pgrepResult.hasConflicts), description=\(pgrepResult.conflictDescription ?? "none")")