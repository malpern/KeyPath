import Foundation

/// ProcessService: thin facade over process lifecycle operations
///
/// Phase 2 Task 1 scaffolding. This service will encapsulate all start/stop/
/// health/cleanup behavior currently spread across KanataManager and
/// ProcessLifecycleManager. Initial commit is a no‑logic wrapper to enable
/// incremental migration without risk.
@MainActor
final class ProcessService: @unchecked Sendable {
    // Dependencies (existing types)
    private let lifecycle: ProcessLifecycleManager

    init(lifecycle: ProcessLifecycleManager = ProcessLifecycleManager()) {
        self.lifecycle = lifecycle
    }

    // MARK: - Lifecyle façade (to be expanded as we migrate)

    func registerStartedProcess(pid: pid_t, command: String) async {
        await lifecycle.registerStartedProcess(pid: pid, command: command)
    }

    func unregisterProcess() async {
        await lifecycle.unregisterProcess()
    }

    func detectConflicts() async -> ProcessLifecycleManager.ConflictResolution {
        await lifecycle.detectConflicts()
    }

    func terminateExternalProcesses() async throws {
        try await lifecycle.terminateExternalProcesses()
    }

    func cleanupOrphansIfNeeded() async {
        await lifecycle.cleanupOrphanedProcesses()
    }

    func invalidatePIDCache() async {
        await lifecycle.invalidatePIDCache()
    }

    // MARK: - LaunchDaemon service management

    /// Start the Kanata LaunchDaemon service via privileged operations facade
    func startLaunchDaemonService() async -> Bool {
        AppLogger.shared.log("🚀 [LaunchDaemon] Starting Kanata service via PrivilegedOperations...")
        return await PrivilegedOperationsProvider.shared.startKanataService()
    }

    /// Stop the Kanata LaunchDaemon service via privileged operations facade
    func stopLaunchDaemonService() async -> Bool {
        AppLogger.shared.log("🛑 [LaunchDaemon] Stopping Kanata service via PrivilegedOperations...")
        let ok = await PrivilegedOperationsProvider.shared.stopKanataService()
        if ok {
            // Wait a moment for graceful shutdown
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return ok
    }

    /// Check the status of the LaunchDaemon service
    func checkLaunchDaemonStatus() async -> (isRunning: Bool, pid: Int?) {
        // Skip actual system calls in test environment
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [TestEnvironment] Skipping launchctl check - returning mock data")
            return (true, nil) // Mock: service loaded but not running
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/com.keypath.kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse the output to find the PID
            if task.terminationStatus == 0 {
                // Look for "pid = XXXX" in the output
                let lines = output.components(separatedBy: .newlines)
                for line in lines where line.contains("pid =") {
                    let components = line.components(separatedBy: "=")
                    if components.count >= 2,
                       let pidString = components[1].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).first,
                       let pid = Int(pidString) {
                        AppLogger.shared.log("🔍 [LaunchDaemon] Service running with PID: \(pid)")
                        return (true, pid)
                    }
                }
                // Service loaded but no PID found (may be starting)
                AppLogger.shared.log("🔍 [LaunchDaemon] Service loaded but PID not found")
                return (true, nil)
            } else {
                AppLogger.shared.log("🔍 [LaunchDaemon] Service not loaded or failed - FIXED VERSION")
                return (false, nil)
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to check service status: \(error)")
            return (false, nil)
        }
    }

    // MARK: - Conflict handling

    /// Resolve any conflicting Kanata processes before starting
    func resolveProcessConflicts() async {
        AppLogger.shared.log("🔍 [Conflict] Checking for conflicting Kanata processes...")

        let conflicts = await lifecycle.detectConflicts()
        let allProcesses = conflicts.managedProcesses + conflicts.externalProcesses

        if !allProcesses.isEmpty {
            AppLogger.shared.log("⚠️ [Conflict] Found \(allProcesses.count) existing Kanata processes")

            for processInfo in allProcesses {
                AppLogger.shared.log("⚠️ [Conflict] Process PID \(processInfo.pid): \(processInfo.command)")

                // Kill non-LaunchDaemon processes
                if !processInfo.command.contains("launchd"), !processInfo.command.contains("system/com.keypath.kanata") {
                    AppLogger.shared.log("🔄 [Conflict] Killing non-LaunchDaemon process: \(processInfo.pid)")
                    await killProcess(pid: Int(processInfo.pid))
                }
            }
        } else {
            AppLogger.shared.log("✅ [Conflict] No conflicting processes found")
        }
    }

    /// Verify no process conflicts exist after starting
    func verifyNoProcessConflicts() async {
        // Wait a moment for any conflicts to surface
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let conflicts = await lifecycle.detectConflicts()
        let managedProcesses = conflicts.managedProcesses
        let conflictProcesses = conflicts.externalProcesses

        AppLogger.shared.log("🔍 [Verify] Process status: \(managedProcesses.count) managed, \(conflictProcesses.count) conflicts")

        // Show managed processes (should be our LaunchDaemon)
        for processInfo in managedProcesses {
            AppLogger.shared.log("✅ [Verify] Managed LaunchDaemon process: PID \(processInfo.pid)")
        }

        // Show any conflicting processes (these are the problem)
        for processInfo in conflictProcesses {
            AppLogger.shared.log("⚠️ [Verify] Conflicting process: PID \(processInfo.pid) - \(processInfo.command)")
        }

        if conflictProcesses.isEmpty {
            AppLogger.shared.log("✅ [Verify] Clean single-process architecture confirmed - no conflicts")
        } else {
            AppLogger.shared.log("⚠️ [Verify] WARNING: \(conflictProcesses.count) conflicting processes detected!")
        }
    }

    /// Kill a specific process by PID
    func killProcess(pid: Int) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["kill", "-TERM", String(pid)]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [Kill] Successfully killed process \(pid)")
            } else {
                AppLogger.shared.log("⚠️ [Kill] Failed to kill process \(pid) (may have already exited)")
            }
        } catch {
            AppLogger.shared.log("❌ [Kill] Exception killing process \(pid): \(error)")
        }
    }
}

// Provide the minimal conflict-detection interface for components that should
// not depend on the full ProcessLifecycleManager type.
extension ProcessService: ProcessLifecycleProviding {}
