import Foundation

/// Simplified ProcessLifecycleManager using PID files for deterministic process ownership
///
/// This replaces the complex regex-based detection with a simple PID file approach:
/// - When we start kanata, we write a PID file
/// - When checking conflicts, we read the PID file to know what we own
/// - No more guessing based on command patterns
@MainActor
enum ProcessLifecycleError: Error {
    case noKanataManager
    case processStartFailed
    case processStopFailed(underlyingError: Error)
    case processTerminateFailed(underlyingError: Error)
}

enum ProcessIntent {
    case shouldBeRunning(source: String)
    case shouldBeStopped
}

final class ProcessLifecycleManager {
    // MARK: - State Variables

    private var currentIntent: ProcessIntent?

    // MARK: - Intent Handling

    func setIntent(_ intent: ProcessIntent) {
        currentIntent = intent
    }

    func reconcileWithIntent() async throws {
        guard let intent = currentIntent else {
            AppLogger.shared.log("❌ [ProcessLifecycleManager] No intent set")
            return
        }

        switch intent {
        case let .shouldBeRunning(source):
            // Logic for ensuring process is running
            AppLogger.shared.log(
                "🚀 [ProcessLifecycleManager] Ensuring process running (source: \(source))")
    // Add actual process start logic here

        case .shouldBeStopped:
            // Logic for ensuring process is stopped
            AppLogger.shared.log("🛑 [ProcessLifecycleManager] Ensuring process is stopped")
            // Add actual process stop logic here
        }
    }

    func recoverFromCrash() async {
        // Default implementation to clean up orphaned processes
        AppLogger.shared.log("🧹 [ProcessLifecycleManager] Attempting to recover from crash")
        try? await cleanupOrphanedProcesses()
    }

    // MARK: - Types

    struct ProcessInfo {
        let pid: pid_t
        let command: String
        let executable: String

        init(pid: pid_t, command: String) {
            self.pid = pid
            self.command = command
            executable = command.components(separatedBy: " ").first ?? ""
        }
    }

    struct ConflictResolution {
        let externalProcesses: [ProcessInfo]
        let managedProcesses: [ProcessInfo]
        let canAutoResolve: Bool

        var hasConflicts: Bool {
            !externalProcesses.isEmpty
        }

        var totalProcesses: Int {
            externalProcesses.count + managedProcesses.count
        }
    }

    // MARK: - State

    private(set) var ownedPID: pid_t?
    private(set) var lastConflictCheck: Date?

    // MARK: - Dependencies

    private let kanataManager: KanataManager?

    init(kanataManager: KanataManager? = nil) {
        self.kanataManager = kanataManager
        AppLogger.shared.log(
            "🏗️ [ProcessLifecycleManager] Initialized with simplified PID-based tracking")
    }

    // MARK: - Public API

    /// Register that we started a kanata process
    func registerStartedProcess(pid: pid_t, command: String) {
        do {
            try PIDFileManager.writePID(pid, command: command)
            ownedPID = pid
            AppLogger.shared.log("📝 [ProcessLifecycleManager] Registered process PID: \(pid)")
        } catch {
            AppLogger.shared.log("❌ [ProcessLifecycleManager] Failed to register process: \(error)")
        }
    }

    /// Unregister our process (on stop or cleanup)
    func unregisterProcess() {
        do {
            try PIDFileManager.removePID()
            ownedPID = nil
            AppLogger.shared.log("🗑️ [ProcessLifecycleManager] Unregistered process")
        } catch {
            AppLogger.shared.log("❌ [ProcessLifecycleManager] Failed to unregister process: \(error)")
        }
    }

    /// Check for conflicts (external kanata processes)
    func detectConflicts() async -> ConflictResolution {
        AppLogger.shared.log("🔍 [ProcessLifecycleManager] Detecting conflicts...")

        // First check our ownership status
        let ownership = PIDFileManager.checkOwnership()
        ownedPID = ownership.pid

        // Get all running kanata processes
        let allProcesses = await detectKanataProcesses()

        // Separate managed processes from external conflicts
        var managedProcesses: [ProcessInfo] = []
        var externalProcesses: [ProcessInfo] = []

        for process in allProcesses {
            let isOwnedPID = ownership.pid != nil && process.pid == ownership.pid

            // Check if process is actually managed by our LaunchDaemon service
            // Just using the config path is not sufficient - need to verify service is running this process
            let isLaunchDaemonManaged = await isProcessManagedByLaunchDaemon(process)

            if isOwnedPID {
                managedProcesses.append(process)
                AppLogger.shared.log(
                    "✅ [ProcessLifecycleManager] Our PID-tracked process: \(process.pid) - \(process.command)"
                )
            } else if isLaunchDaemonManaged {
                managedProcesses.append(process)
                AppLogger.shared.log(
                    "✅ [ProcessLifecycleManager] Our LaunchDaemon-managed process: \(process.pid) - \(process.command)"
                )
            } else {
                externalProcesses.append(process)
                AppLogger.shared.log(
                    "⚠️ [ProcessLifecycleManager] External conflict process: \(process.pid) - \(process.command)"
                )
            }
        }

        AppLogger.shared.log(
            "🔍 [ProcessLifecycleManager] Process summary: \(managedProcesses.count) managed, \(externalProcesses.count) conflicts"
        )

        lastConflictCheck = Date()

        return ConflictResolution(
            externalProcesses: externalProcesses,
            managedProcesses: managedProcesses,
            canAutoResolve: true // We can always kill external processes
        )
    }

    /// Kill all external kanata processes
    func terminateExternalProcesses() async throws {
        let conflicts = await detectConflicts()

        for process in conflicts.externalProcesses {
            AppLogger.shared.log(
                "💀 [ProcessLifecycleManager] Terminating external process PID: \(process.pid)")

            // Try graceful termination
            kill(process.pid, SIGTERM)
        }

        // Wait for processes to terminate
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Force kill any remaining
        let remainingConflicts = await detectConflicts()
        for process in remainingConflicts.externalProcesses {
            AppLogger.shared.log("💀 [ProcessLifecycleManager] Force killing process PID: \(process.pid)")
            kill(process.pid, SIGKILL)
        }
    }

    /// Clean up orphaned processes on app startup
    func cleanupOrphanedProcesses() async {
        AppLogger.shared.log("🧹 [ProcessLifecycleManager] Checking for orphaned processes...")

        // Check if we have a PID file from a previous run
        if let record = PIDFileManager.readPID() {
            if PIDFileManager.isProcessRunning(pid: record.pid) {
                AppLogger.shared.log(
                    "⚠️ [ProcessLifecycleManager] Found orphaned process from previous run: PID \(record.pid)")

                // Kill the orphaned process
                await PIDFileManager.killOrphanedProcess()
            } else {
                // Process is dead, just clean up the PID file
                try? PIDFileManager.removePID()
            }
        }
    }

    // MARK: - Process Detection

    /// Detect all kanata processes currently running
    private func detectKanataProcesses() async -> [ProcessInfo] {
        AppLogger.shared.log("🔍 [ProcessLifecycleManager] Detecting kanata processes...")

        var processes: [ProcessInfo] = []

        // Use pgrep to find processes
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fl", "kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

                for line in lines {
                    let components = line.components(separatedBy: " ")
                    guard let pidString = components.first,
                          let pid = pid_t(pidString),
                          components.count > 1
                    else {
                        continue
                    }

                    let command = components.dropFirst().joined(separator: " ")

                    // Only include actual kanata binaries
                    if isKanataBinary(command) {
                        let processInfo = ProcessInfo(pid: pid, command: command)
                        processes.append(processInfo)
                        AppLogger.shared.log("🔍 [ProcessLifecycleManager] Found kanata process: PID=\(pid)")
                    }
                }
            }
        } catch {
            AppLogger.shared.log("❌ [ProcessLifecycleManager] Error detecting processes: \(error)")
        }

        AppLogger.shared.log("🔍 [ProcessLifecycleManager] Found \(processes.count) kanata processes")
        return processes
    }

    /// Simple check for actual kanata binaries (not editor plugins etc)
    private func isKanataBinary(_ command: String) -> Bool {
        // Skip pgrep itself and editor extensions
        if command.contains("pgrep") || command.contains("vscode") || command.contains(".cursor") {
            return false
        }

        // Skip log monitoring and other utilities that contain "kanata" in paths
        if command.contains("tail") || command.contains("cat") || command.contains("grep")
            || command.contains("less") || command.contains("vim") || command.contains("nano") {
            return false
        }

        // Look for actual kanata binary - be more specific
        return command.contains("/bin/kanata") || command.hasPrefix("kanata ") || command == "kanata"
    }

    /// Check if a process is actually managed by our LaunchDaemon service
    /// This verifies the service is loaded AND that the specific PID belongs to the service
    private func isProcessManagedByLaunchDaemon(_ process: ProcessInfo) async -> Bool {
        // First check if the process uses our config path (necessary but not sufficient)
        guard process.command.contains("/.config/keypath/keypath.kbd") else {
            return false
        }

        // Check if our LaunchDaemon service is loaded and get its PID
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["print", "system/com.keypath.kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Discard error output

        do {
            try task.run()
            task.waitUntilExit()

            // If launchctl print succeeds, the service is loaded
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                // Extract the actual PID from the LaunchDaemon output
                // Look for pattern like "pid = 97324"
                var launchDaemonPID: pid_t?
                if let pidRange = output.range(of: "pid = ") {
                    let pidStart = output.index(pidRange.upperBound, offsetBy: 0)
                    // Find the end of the PID number
                    var pidEnd = pidStart
                    while pidEnd < output.endIndex && output[pidEnd].isNumber {
                        pidEnd = output.index(after: pidEnd)
                    }
                    
                    let pidString = String(output[pidStart..<pidEnd])
                    launchDaemonPID = pid_t(pidString)
                }

                let isRunning = output.contains("state = running")
                
                // Only return true if this specific process PID matches the LaunchDaemon's PID
                let isThisProcessManaged = launchDaemonPID != nil && launchDaemonPID == process.pid

                AppLogger.shared.log("🔍 [ProcessLifecycleManager] LaunchDaemon check for PID \(process.pid): service_pid=\(launchDaemonPID ?? -1), running=\(isRunning), matches=\(isThisProcessManaged)")

                return isThisProcessManaged
            } else {
                AppLogger.shared.log("🔍 [ProcessLifecycleManager] LaunchDaemon service check: not loaded")
                return false
            }
        } catch {
            AppLogger.shared.log("🔍 [ProcessLifecycleManager] LaunchDaemon service check failed: \(error)")
            return false
        }
    }
}
