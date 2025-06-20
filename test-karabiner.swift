#!/usr/bin/env swift

import Foundation

class KanataInstaller {
    func isKarabinerRunning() -> Bool {
        print("🔧 Starting Karabiner detection...")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["pgrep", "-f", "karabiner_grabber|karabiner_observer|Karabiner-Elements"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            print("🔧 Running pgrep command...")
            try task.run()
            task.waitUntilExit()
            print("🔧 pgrep completed with status: \(task.terminationStatus)")
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("🔧 pgrep output: '\(output)'")
                
                // Double-check by looking for actual Karabiner-Elements processes
                print("🔧 Running ps verification...")
                let verifyTask = Process()
                verifyTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                verifyTask.arguments = ["ps", "-ax"]
                
                let verifyPipe = Pipe()
                verifyTask.standardOutput = verifyPipe
                
                try verifyTask.run()
                verifyTask.waitUntilExit()
                print("🔧 ps completed with status: \(verifyTask.terminationStatus)")
                
                let verifyData = verifyPipe.fileHandleForReading.readDataToEndOfFile()
                let processOutput = String(data: verifyData, encoding: .utf8) ?? ""
                
                let hasKarabinerGrabber = processOutput.contains("karabiner_grabber")
                let hasKarabinerObserver = processOutput.contains("karabiner_observer") 
                let hasKarabinerElements = processOutput.contains("Karabiner-Elements")
                
                print("🔧 Has karabiner_grabber: \(hasKarabinerGrabber)")
                print("🔧 Has karabiner_observer: \(hasKarabinerObserver)")
                print("🔧 Has Karabiner-Elements: \(hasKarabinerElements)")
                
                return hasKarabinerGrabber || hasKarabinerObserver || hasKarabinerElements
            }
        } catch {
            print("🔧 Failed to check for Karabiner processes: \(error)")
        }
        
        print("🔧 Karabiner detection completed - no conflicts found")
        return false
    }
}

print("Testing Karabiner Detection...")
let installer = KanataInstaller()
let result = installer.isKarabinerRunning()
print("🔧 Final result: Karabiner running = \(result)")