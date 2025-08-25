#!/usr/bin/env swift

import Foundation

print("🔮 ORACLE LIVE TEST - Monitoring KeyPath Logs")
print(String(repeating: "=", count: 50))
print()

print("📋 Instructions:")
print("1. KeyPath.app should be running")
print("2. This will tail the logs to see Oracle in action")
print("3. Look for '🔮 [Oracle]' entries")
print("4. Test permission changes in System Settings")
print()

print("🔍 Monitoring KeyPath logs for Oracle activity...")
print("   (Press Ctrl+C to stop)")
print()

// Create log monitoring process
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
task.arguments = [
    "stream",
    "--predicate", "processImagePath CONTAINS 'KeyPath' AND (composedMessage CONTAINS 'Oracle' OR composedMessage CONTAINS '🔮')",
    "--style", "compact"
]

// Redirect output to show Oracle logs
let pipe = Pipe()
task.standardOutput = pipe

do {
    try task.run()

    // Read and display Oracle logs in real-time
    let handle = pipe.fileHandleForReading

    while task.isRunning {
        let data = handle.availableData
        if !data.isEmpty {
            if let output = String(data: data, encoding: .utf8) {
                // Highlight Oracle entries
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if !line.isEmpty {
                        if line.contains("🔮") || line.contains("Oracle") {
                            print("🔮 \(line)")
                        } else {
                            print("   \(line)")
                        }
                    }
                }
            }
        }

        // Small delay to prevent CPU spinning
        Thread.sleep(forTimeInterval: 0.1)
    }
} catch {
    print("❌ Error monitoring logs: \(error)")
    print()
    print("💡 Alternative: Open Console.app and search for 'Oracle' or '🔮'")
    print("   - Filter by Process: KeyPath")
    print("   - Look for permission detection logs")
}
