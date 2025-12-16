import Foundation

/// KeyPathIMAgent: per-user launcher to request Input Monitoring for Kanata
/// - Runs inside the logged-in user session as a LoginItem (SMAppService agent)
/// - Triggers the Input Monitoring prompt by invoking the active kanata binary
///   with `--permission-probe` (a macOS-only hidden flag in the CLI build).
/// - Exits after the probe completes; the root LaunchDaemon will be restarted by the wizard

@main
struct KeyPathIMAgent {
    static func main() {
        do {
            let kanataPath = try resolveKanataPath()
            let status = try runProbe(at: kanataPath)
            if status != 0 { fputs("KeyPathIMAgent: probe exited with status \(status)\n", stderr) }
        } catch {
            fputs("KeyPathIMAgent error: \(error)\n", stderr)
        }
    }

    private static func resolveKanataPath() throws -> String {
        // We always request Input Monitoring for the system-installed kanata binary.
        // TCC grants are path-specific for CLI binaries, and the system path is stable across
        // app updates (unlike the app bundle path).
        let systemPath = "/Library/KeyPath/bin/kanata"
        guard FileManager.default.isExecutableFile(atPath: systemPath) else {
            throw NSError(domain: "KeyPathIMAgent", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "Kanata is not installed at \(systemPath). Complete the Kanata Service install step first, then retry."
            ])
        }
        return systemPath
    }

    @discardableResult
    private static func runProbe(at path: String) throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["--permission-probe"]
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }
}
