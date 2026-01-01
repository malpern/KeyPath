import Foundation
import KeyPathCore

/// Service for detecting and stopping external (non-KeyPath managed) Kanata processes
/// Used during migration to take over keyboard control from an existing Kanata installation
public enum ExternalKanataService {
    // MARK: - Types

    public enum StopResult {
        case success
        case processNotFound
        case killFailed(Error)
        case launchAgentDisableFailed(Error)
    }

    // MARK: - Public API

    /// Stop an external Kanata process and disable its LaunchAgent if present
    /// - Parameter info: Information about the running Kanata process
    /// - Returns: Result of the stop operation
    public static func stopExternalKanata(_ info: WizardSystemPaths.RunningKanataInfo) async -> StopResult {
        AppLogger.shared.log("🛑 [ExternalKanata] Stopping external Kanata (PID: \(info.pid))")

        // First, disable any LaunchAgents to prevent restart
        let launchAgentPaths = WizardSystemPaths.userKanataLaunchAgentPaths
        for agentPath in launchAgentPaths {
            do {
                try await disableLaunchAgent(at: agentPath)
                AppLogger.shared.log("✅ [ExternalKanata] Disabled LaunchAgent: \(agentPath)")
            } catch {
                AppLogger.shared.warn("⚠️ [ExternalKanata] Failed to disable LaunchAgent: \(error)")
                // Continue anyway - we'll still try to kill the process
            }
        }

        // Then kill the process
        do {
            try await killProcess(pid: info.pid)
            AppLogger.shared.log("✅ [ExternalKanata] Successfully stopped external Kanata")
            return .success
        } catch {
            AppLogger.shared.error("❌ [ExternalKanata] Failed to kill process: \(error)")
            return .killFailed(error)
        }
    }

    /// Check if there's an external (non-KeyPath) Kanata process running
    public static func hasExternalKanataRunning() -> Bool {
        guard let info = WizardSystemPaths.detectRunningKanataProcess() else {
            return false
        }
        return !info.isKeyPathManaged
    }

    /// Get info about running external Kanata, or nil if none/only KeyPath-managed
    public static func getExternalKanataInfo() -> WizardSystemPaths.RunningKanataInfo? {
        guard let info = WizardSystemPaths.detectRunningKanataProcess(),
              !info.isKeyPathManaged else {
            return nil
        }
        return info
    }

    // MARK: - Private Helpers

    private static func killProcess(pid: Int) async throws {
        // Try graceful kill first (SIGTERM)
        let termResult = try await runCommand("/bin/kill", arguments: ["-TERM", String(pid)])

        if termResult.status == 0 {
            // Wait a moment for graceful shutdown
            try? await Task.sleep(for: .milliseconds(500))

            // Check if still running
            let checkResult = try await runCommand("/bin/kill", arguments: ["-0", String(pid)])
            if checkResult.status != 0 {
                // Process exited
                return
            }

            // Force kill if still running
            _ = try await runCommand("/bin/kill", arguments: ["-9", String(pid)])
        } else if termResult.status == 1 {
            // Process doesn't exist - that's fine
            return
        } else {
            throw NSError(
                domain: "ExternalKanataService",
                code: Int(termResult.status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to kill process: \(termResult.stderr)"]
            )
        }
    }

    private static func disableLaunchAgent(at path: String) async throws {
        // Get the label from the plist
        guard let label = extractLabelFromPlist(at: path) else {
            AppLogger.shared.warn("⚠️ [ExternalKanata] Could not extract label from: \(path)")
            return
        }

        // Unload the LaunchAgent
        let unloadResult = try await runCommand(
            "/bin/launchctl",
            arguments: ["unload", "-w", path]
        )

        if unloadResult.status != 0 && !unloadResult.stderr.contains("Could not find") {
            throw NSError(
                domain: "ExternalKanataService",
                code: Int(unloadResult.status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to unload LaunchAgent: \(unloadResult.stderr)"]
            )
        }

        // Optionally disable (prevents future auto-load)
        _ = try? await runCommand(
            "/bin/launchctl",
            arguments: ["disable", "gui/\(getuid())/\(label)"]
        )
    }

    private static func extractLabelFromPlist(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String else {
            return nil
        }
        return label
    }

    private struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static func runCommand(_ executable: String, arguments: [String]) async throws -> CommandResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        try task.run()
        task.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            status: task.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
