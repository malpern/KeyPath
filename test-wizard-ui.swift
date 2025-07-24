#!/usr/bin/swift

import Foundation

// Simulate the exact same logic as the wizard
class TestInstaller {
    var hasConflicts = false
    var conflictDescription = ""
    
    func testConflictDetection() -> (conflicts: Bool, description: String) {
        print("🔍 [Test] Starting conflict detection test...")
        
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
                return (false, "")
            }
            
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            print("🔍 [Test] Found \(lines.count) process(es)")
            
            var rootProcessCount = 0
            
            for line in lines {
                print("🔍 [Test] Process: \(line)")
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
            } else if lines.count > 0 {
                let message = "Found \(lines.count) existing Kanata process(es) that need to be terminated before KeyPath can manage its own instance."
                print("🔍 [Test] ❌ CONFLICTS DETECTED: \(message)")
                return (true, message)
            }
            
            print("🔍 [Test] ✅ No conflicting Kanata processes found")
            return (false, "")
            
        } catch {
            print("🔍 [Test] pgrep failed: \(error)")
            return (false, "")
        }
    }
    
    func simulateWizardLogic() {
        print("🔍 [Test] ========== SIMULATING WIZARD LOGIC ==========")
        
        let (hasConflictingProcesses, conflictDesc) = testConflictDetection()
        hasConflicts = hasConflictingProcesses
        conflictDescription = conflictDesc
        
        print("🔍 [Test] Conflict detection results:")
        print("🔍 [Test]   hasConflicts: \(hasConflicts)")
        print("🔍 [Test]   description: '\(conflictDescription)'")
        
        if hasConflicts {
            print("🔍 [Test] ❌ CONFLICTS DETECTED: \(conflictDescription)")
            print("🔍 [Test] 🛑 WOULD STOP ALL OTHER CHECKS DUE TO CONFLICTS")
            print("🔍 [Test] UI SHOULD SHOW: Conflict detection as Step 0 with red status")
            print("🔍 [Test] UI SHOULD HIDE: All other installation steps")
        } else {
            print("🔍 [Test] ✅ No conflicts detected, would proceed with installation checks...")
            print("🔍 [Test] UI SHOULD SHOW: Regular installation steps 1-4")
        }
    }
}

let installer = TestInstaller()
installer.simulateWizardLogic()