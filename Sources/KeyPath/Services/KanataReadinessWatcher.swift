import Foundation

/// Watches macOS unified logs for a short window to detect Kanata readiness signal.
/// Specifically, looks for the line containing "driver_connected 1".
enum KanataReadinessWatcher {
    /// Waits up to timeoutSeconds for a readiness signal.
    /// Returns true if observed, false on timeout or error.
    static func waitForDriverConnected(timeoutSeconds: Double = 2.5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            // Use log show with small lookback to avoid persistent stream complexity
            let ok = runLogCheck()
            if ok { return true }
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms backoff
        }
        return false
    }

    private static func runLogCheck() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = [
            "show",
            "--style", "syslog",
            "--last", "2s",
            "--predicate", "eventMessage CONTAINS 'driver_connected 1'"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return false }
            return output.contains("driver_connected 1")
        } catch {
            return false
        }
    }
}


