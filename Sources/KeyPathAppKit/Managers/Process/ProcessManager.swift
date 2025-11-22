import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle

/// Protocol for managing Kanata process lifecycle
protocol ProcessManaging: Sendable {
    /// Start the Kanata service with the given configuration
    func startService(configPath: String, arguments: [String]) async -> Bool

    /// Stop the Kanata service
    func stopService() async -> Bool

    /// Restart the Kanata service
    func restartService(configPath: String, arguments: [String]) async -> Bool

    /// Check the current service status
    func status() async -> (isRunning: Bool, pid: Int?)

    /// Resolve any process conflicts before starting
    func resolveConflicts() async

    /// Verify no process conflicts exist after starting
    func verifyNoConflicts() async

    /// Cleanup when app terminates
    func cleanup() async
}

/// Manages Kanata process lifecycle using LaunchDaemon
final class ProcessManager: ProcessManaging, @unchecked Sendable {
    private let processLifecycleManager: ProcessLifecycleManager
    private let karabinerConflictService: KarabinerConflictManaging

    init(
        processLifecycleManager: ProcessLifecycleManager,
        karabinerConflictService: KarabinerConflictManaging
    ) {
        self.processLifecycleManager = processLifecycleManager
        self.karabinerConflictService = karabinerConflictService
    }

    func startService(configPath _: String, arguments: [String]) async -> Bool {
        AppLogger.shared.log("🚀 [ProcessManager] Starting Kanata LaunchDaemon service...")

        // Resolve any conflicts first
        await resolveConflicts()

        // Start the LaunchDaemon service
        let success = await startLaunchDaemonService()

        if success {
            // Wait a moment for service to initialize
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Verify service started successfully
            let serviceStatus = await checkLaunchDaemonStatus()
            if let pid = serviceStatus.pid {
                AppLogger.shared.log("📝 [ProcessManager] LaunchDaemon service started with PID: \(pid)")

                // Register with lifecycle manager
                let command = arguments.joined(separator: " ")
                await processLifecycleManager.registerStartedProcess(
                    pid: Int32(pid), command: "launchd: \(command)"
                )

                // Check for process conflicts after starting
                await verifyNoConflicts()

                AppLogger.shared.log(
                    "✅ [ProcessManager] Successfully started Kanata LaunchDaemon service (PID: \(pid))")
                return true
            } else {
                AppLogger.shared.log(
                    "⚠️ [ProcessManager] Service started but no PID found - may still be initializing")
                return false
            }
        } else {
            AppLogger.shared.log("❌ [ProcessManager] Failed to start LaunchDaemon service")
            return false
        }
    }

    func stopService() async -> Bool {
        AppLogger.shared.log("🛑 [ProcessManager] Stopping Kanata LaunchDaemon service...")

        // Stop the LaunchDaemon service
        let success = await stopLaunchDaemonService()

        if success {
            AppLogger.shared.log("✅ [ProcessManager] Successfully stopped Kanata LaunchDaemon service")

            // Unregister from lifecycle manager
            await processLifecycleManager.unregisterProcess()
            return true
        } else {
            AppLogger.shared.log("⚠️ [ProcessManager] Failed to stop Kanata LaunchDaemon service")
            return false
        }
    }

    func restartService(configPath: String, arguments: [String]) async -> Bool {
        AppLogger.shared.log("🔄 [ProcessManager] Restarting Kanata...")
        let stopped = await stopService()
        guard stopped else {
            AppLogger.shared.log("⚠️ [ProcessManager] Failed to stop service during restart")
            return false
        }
        return await startService(configPath: configPath, arguments: arguments)
    }

    func status() async -> (isRunning: Bool, pid: Int?) {
        await checkLaunchDaemonStatus()
    }

    func resolveConflicts() async {
        AppLogger.shared.log("🔍 [ProcessManager] Checking for conflicting Kanata processes...")

        let conflicts = await processLifecycleManager.detectConflicts()
        let allProcesses = conflicts.managedProcesses + conflicts.externalProcesses

        if !allProcesses.isEmpty {
            AppLogger.shared.log(
                "⚠️ [ProcessManager] Found \(allProcesses.count) existing Kanata processes")

            for processInfo in allProcesses {
                AppLogger.shared.log(
                    "⚠️ [ProcessManager] Process PID \(processInfo.pid): \(processInfo.command)")
            }

            // Terminate only external processes via lifecycle manager
            do {
                try await processLifecycleManager.terminateExternalProcesses()
            } catch {
                AppLogger.shared.log("⚠️ [ProcessManager] Failed to terminate external processes: \(error)")
            }
        } else {
            AppLogger.shared.log("✅ [ProcessManager] No conflicting processes found")
        }
    }

    func verifyNoConflicts() async {
        // Wait a moment for any conflicts to surface
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let conflicts = await processLifecycleManager.detectConflicts()
        let managedProcesses = conflicts.managedProcesses
        let conflictProcesses = conflicts.externalProcesses

        AppLogger.shared.log(
            "🔍 [ProcessManager] Process status: \(managedProcesses.count) managed, \(conflictProcesses.count) conflicts"
        )

        // Show managed processes (should be our LaunchDaemon)
        for processInfo in managedProcesses {
            AppLogger.shared.log(
                "✅ [ProcessManager] Managed LaunchDaemon process: PID \(processInfo.pid)")
        }

        // Show any conflicting processes (these are the problem)
        for processInfo in conflictProcesses {
            AppLogger.shared.log(
                "⚠️ [ProcessManager] Conflicting process: PID \(processInfo.pid) - \(processInfo.command)")
        }

        if conflictProcesses.isEmpty {
            AppLogger.shared.log(
                "✅ [ProcessManager] Clean single-process architecture confirmed - no conflicts")
        } else {
            AppLogger.shared.log(
                "⚠️ [ProcessManager] WARNING: \(conflictProcesses.count) conflicting processes detected!")
        }
    }

    func cleanup() async {
        _ = await stopService()
    }

    // MARK: - Private Helper Methods

    /// Start the LaunchDaemon service via privileged operations facade
    private func startLaunchDaemonService() async -> Bool {
        AppLogger.shared.log("🚀 [ProcessManager] Starting Kanata service via PrivilegedOperations...")
        return await PrivilegedOperationsProvider.shared.startKanataService()
    }

    /// Stop the Kanata LaunchDaemon service via privileged operations facade
    private func stopLaunchDaemonService() async -> Bool {
        AppLogger.shared.log("🛑 [ProcessManager] Stopping Kanata service via PrivilegedOperations...")
        let ok = await PrivilegedOperationsProvider.shared.stopKanataService()
        if ok {
            // Wait a moment for graceful shutdown
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return ok
    }

    /// Check LaunchDaemon service status
    private func checkLaunchDaemonStatus() async -> (isRunning: Bool, pid: Int?) {
        AppLogger.shared.log("🔍 [ProcessManager] Checking LaunchDaemon service status...")

        // Skip actual system calls in test environment
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [ProcessManager] Skipping launchctl check - returning mock data")
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

            // Parse PID from launchctl output
            // Format: "pid = 12345"
            var pid: Int?
            for line in output.components(separatedBy: "\n") where line.contains("pid =") {
                let components = line.components(separatedBy: "=")
                if components.count == 2 {
                    let pidString = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    pid = Int(pidString)
                    break
                }
            }

            // Service is running if we got a PID
            let isRunning = pid != nil
            if isRunning {
                AppLogger.shared.log("✅ [ProcessManager] Service is running with PID: \(pid!)")
            } else {
                AppLogger.shared.log("⚠️ [ProcessManager] Service status check returned no PID")
            }
            return (isRunning, pid)
        } catch {
            AppLogger.shared.log("❌ [ProcessManager] Failed to check service status: \(error)")
            return (false, nil)
        }
    }
}
