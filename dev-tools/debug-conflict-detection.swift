#!/usr/bin/swift

import Foundation

func hasConflictingKanataProcesses() -> (hasConflicts: Bool, conflictDescription: String?) {
    print("🔍 [Debug] Checking for conflicting Kanata processes...")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["aux"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
        try task.run()

        // Wait with timeout
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            task.waitUntilExit()
            semaphore.signal()
        }

        let timeoutResult = semaphore.wait(timeout: .now() + 15.0) // 15 second timeout

        if timeoutResult == .timedOut {
            print("🔍 [Debug] Process check timed out, terminating...")
            task.terminate()
            return (false, nil)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        print("🔍 [Debug] Raw ps output length: \(output.count)")

        let lines = output.components(separatedBy: .newlines)
        let kanataLines = lines.filter {
            $0.contains("kanata-cmd") &&
            !$0.contains("grep") &&
            !$0.contains("KeyPath") // Don't count KeyPath's own process checks
        }

        print("🔍 [Debug] Process check completed. Found \(kanataLines.count) potential Kanata process(es)")

        if !kanataLines.isEmpty {
            print("🔍 [Debug] Kanata processes found:")
            for (index, line) in kanataLines.enumerated() {
                print("🔍 [Debug] [\(index + 1)] \(line)")
            }

            // Check if any are running as root
            let rootProcesses = kanataLines.filter { $0.hasPrefix("root") }
            if !rootProcesses.isEmpty {
                print("🔍 [Debug] Found \(rootProcesses.count) root process(es)")
                return (true, "Found \(rootProcesses.count) Kanata process(es) running as root that need to be terminated before KeyPath can manage its own Kanata instance.")
            } else {
                print("🔍 [Debug] Found \(kanataLines.count) user process(es)")
                return (true, "Found \(kanataLines.count) existing Kanata process(es) that need to be terminated before KeyPath can manage its own instance.")
            }
        }

        print("🔍 [Debug] No conflicting Kanata processes found")
        return (false, nil)
    } catch {
        print("🔍 [Debug] Failed to check for conflicts: \(error)")
        return (false, nil)
    }
}

// Test the function
let result = hasConflictingKanataProcesses()
print("🔍 [Debug] Final result: hasConflicts=\(result.hasConflicts), description=\(result.conflictDescription ?? "none")")
