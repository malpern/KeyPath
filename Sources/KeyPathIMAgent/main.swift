import Foundation

/// KeyPathIMAgent: per-user launcher to request Input Monitoring for Kanata
/// - Runs inside the logged-in user session as a LoginItem (SMAppService agent)
/// - Triggers the Input Monitoring prompt by invoking the bundled kanata binary
///   with the --permission-probe flag (non-driver path, safe to run as user)
/// - Exits after the probe completes; the root LaunchDaemon will be restarted by the wizard

@main
struct KeyPathIMAgent {
    static func main() {
        do {
            let kanataPath = try resolveKanataPath()
            let status = try runProbe(at: kanataPath)
            if status != 0 {
                fputs("KeyPathIMAgent: probe exited with status \(status)\n", stderr)
            }
        } catch {
            fputs("KeyPathIMAgent error: \(error)\n", stderr)
        }
    }

    private static func resolveKanataPath() throws -> String {
        // Prefer the system-installed path if present, because that is what the daemon
        // typically runs. TCC grants are path-specific for CLI binaries.
        let systemPath = "/Library/KeyPath/bin/kanata"
        if FileManager.default.isExecutableFile(atPath: systemPath) {
            return systemPath
        }

        // Start from executable path to avoid surprises when Bundle resolution differs.
        // Executable: KeyPath.app/Contents/Library/LoginItems/KeyPathIMAgent.app/Contents/MacOS/KeyPathIMAgent
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let appURL = execURL
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents (of agent)
            .deletingLastPathComponent() // KeyPathIMAgent.app
            .deletingLastPathComponent() // LoginItems
            .deletingLastPathComponent() // Library
            .deletingLastPathComponent() // Contents (of main app)
            .deletingLastPathComponent() // KeyPath.app
        let kanataURL = appURL.appendingPathComponent("Contents/Library/KeyPath/kanata", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: kanataURL.path) else {
            throw NSError(domain: "KeyPathIMAgent", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Kanata binary not found at \(kanataURL.path)"
            ])
        }
        return kanataURL.path
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
