import Foundation
import KeyPathCore

/// Simplified ProcessLifecycleManager using PID files for deterministic process ownership
///
/// This replaces the complex regex-based detection with a simple PID file approach:
/// - When we start kanata, we write a PID file
/// - When checking conflicts, we read the PID file to know what we own
/// - No more guessing based on command patterns
@MainActor
public final class ProcessLifecycleManager: @unchecked Sendable {
    // MARK: - Intent

    public enum ProcessIntent {
        case shouldBeRunning(source: String)
        case shouldBeStopped
    }

    private var currentIntent: ProcessIntent?

    public func setIntent(_ intent: ProcessIntent) {
        currentIntent = intent
    }

    public func reconcileWithIntent() async throws {
        guard let intent = currentIntent else {
            AppLogger.shared.log("❌ [ProcessLifecycleManager] No intent set")
            return
        }

        switch intent {
        case let .shouldBeRunning(source):
            AppLogger.shared.log(
                "🚀 [ProcessLifecycleManager] Ensuring process running (source: \(source))")
        // Add actual process start logic here
        case .shouldBeStopped:
            AppLogger.shared.log("🛑 [ProcessLifecycleManager] Ensuring process is stopped")
            // Add actual process stop logic here
        }
    }

    public init() {
        AppLogger.shared.log(
            "🏗️ [ProcessLifecycleManager] Initialized with simplified PID-based tracking and caching")
    }

    // MARK: - Types

    public struct ProcessInfo: Sendable {
        public let pid: pid_t
        public let command: String
        public let executable: String

        public init(pid: pid_t, command: String) {
            self.pid = pid
            self.command = command
            executable = command.components(separatedBy: " ").first ?? ""
        }
    }

    public struct ConflictResolution: Sendable {
        public let externalProcesses: [ProcessInfo]
        public let managedProcesses: [ProcessInfo]
        public let canAutoResolve: Bool

        public init(
            externalProcesses: [ProcessInfo], managedProcesses: [ProcessInfo], canAutoResolve: Bool
        ) {
            self.externalProcesses = externalProcesses
            self.managedProcesses = managedProcesses
            self.canAutoResolve = canAutoResolve
        }

        public var hasConflicts: Bool { !externalProcesses.isEmpty }
        public var totalProcesses: Int { externalProcesses.count + managedProcesses.count }
    }

    // MARK: - State

    public private(set) var ownedPID: pid_t?
    public private(set) var lastConflictCheck: Date?

    // MARK: - Dependencies

    private let pidCache = LaunchDaemonPIDCache()

    // MARK: - Public API

    /// Register that we started a kanata process
    public func registerStartedProcess(pid: pid_t, command: String) async {
        do {
            try PIDFileManager.writePID(pid, command: command)
            ownedPID = pid
            // Invalidate cache since we changed process state
            await pidCache.invalidateCache()
            AppLogger.shared.log("📝 [ProcessLifecycleManager] Registered process PID: \(pid)")
        } catch {
            AppLogger.shared.log("❌ [ProcessLifecycleManager] Failed to register process: \(error)")
        }
    }

    /// Unregister our process (on stop or cleanup)
    public func unregisterProcess() async {
        do {
            try PIDFileManager.removePID()
            ownedPID = nil
            // Invalidate cache since we changed process state
            await pidCache.invalidateCache()
            AppLogger.shared.log("🗑️ [ProcessLifecycleManager] Unregistered process")
        } catch {
            AppLogger.shared.log("❌ [ProcessLifecycleManager] Failed to unregister process: \(error)")
        }
    }

    /// Check for conflicts (external kanata processes)
    public func detectConflicts() async -> ConflictResolution {
        AppLogger.shared.log("🔍 [ProcessLifecycleManager] Detecting conflicts...")

        // Skip process detection in test environment
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log(
                "🧪 [TestEnvironment] Skipping process conflict detection - returning clean state")
            return ConflictResolution(
                externalProcesses: [],
                managedProcesses: [],
                canAutoResolve: true
            )
        }

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
    public func terminateExternalProcesses() async throws {
        let conflicts = await detectConflicts()

        for process in conflicts.externalProcesses {
            AppLogger.shared.log(
                "💀 [ProcessLifecycleManager] Terminating external process PID: \(process.pid)")

            // Try graceful termination
            Foundation.kill(process.pid, SIGTERM)
        }

        // Wait for processes to terminate
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Force kill any remaining
        let remainingConflicts = await detectConflicts()
        for process in remainingConflicts.externalProcesses {
            AppLogger.shared.log("💀 [ProcessLifecycleManager] Force killing process PID: \(process.pid)")
            Foundation.kill(process.pid, SIGKILL)
        }
    }

    /// Clean up orphaned processes on app startup
    public func cleanupOrphanedProcesses() async {
        AppLogger.shared.log("🧹 [ProcessLifecycleManager] Checking for orphaned processes...")

        // Check if we have a PID file from a previous run
        if let record = PIDFileManager.readPID() {
            if PIDFileManager.isProcessRunning(pid: record.pid) {
                AppLogger.shared.log(
                    "⚠️ [ProcessLifecycleManager] Found orphaned process from previous run: PID \(record.pid)")

                // Kill the orphaned process
                await PIDFileManager.killOrphanedProcess()
                // Invalidate cache since we changed process state
                await pidCache.invalidateCache()
            } else {
                // Process is dead, just clean up the PID file
                try? PIDFileManager.removePID()
            }
        }
    }

    /// Force refresh of LaunchDaemon PID cache
    /// Useful when external processes modify service state
    public func invalidatePIDCache() async {
        await pidCache.invalidateCache()
        AppLogger.shared.log("🔄 [ProcessLifecycleManager] PID cache invalidated externally")
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
            || command.contains("less") || command.contains("vim") || command.contains("nano")
        {
            return false
        }

        // Check against all known kanata paths (bundled, homebrew, standard locations)
        let knownPaths = WizardSystemPaths.allKnownKanataPaths()
        for path in knownPaths where command.contains(path) {
            return true
        }

        // Look for actual kanata binary - be more specific
        return command.contains("/bin/kanata") || command.hasPrefix("kanata ") || command == "kanata"
    }

    /// Check if a process is actually managed by our LaunchDaemon service
    /// This verifies the service is loaded AND that the specific PID belongs to the service
    /// Uses cached PID lookups to prevent race conditions and improve performance
    private func isProcessManagedByLaunchDaemon(_ process: ProcessInfo) async -> Bool {
        // First check if the process uses our config path (necessary but not sufficient)
        guard process.command.contains("/.config/keypath/keypath.kbd") else {
            AppLogger.shared.log(
                "🔍 [ProcessLifecycleManager] PID \(process.pid): Wrong config path, not managed")
            return false
        }

        // Use cached PID lookup with timeout protection and confidence tracking
        let (cachedPID, confidence) = await pidCache.getCachedPIDWithConfidence()
        let isThisProcessManaged = cachedPID != nil && cachedPID == process.pid

        let cacheAge = await pidCache.lastUpdate.map { Date().timeIntervalSince($0) } ?? -1

        AppLogger.shared.log(
            "🔍 [ProcessLifecycleManager] PID \(process.pid): " + "ConfigPath=✅, "
                + "CachedPID=\(cachedPID ?? -1), " + "Match=\(isThisProcessManaged), "
                + "Confidence=\(confidence), " + "CacheAge=\(String(format: "%.1f", cacheAge))s"
        )

        return isThisProcessManaged
    }
}
