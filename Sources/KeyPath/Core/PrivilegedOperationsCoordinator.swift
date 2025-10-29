import Foundation
import AppKit

/// Coordinates all privileged operations with hybrid approach (helper vs direct sudo)
///
/// **Architecture:** This coordinator implements the hybrid strategy from HELPER.md
/// - DEBUG builds: Use direct sudo (AuthorizationExecuteWithPrivileges)
/// - RELEASE builds: Prefer privileged helper if available, fall back to sudo
///
/// **Usage:**
/// ```swift
/// let coordinator = PrivilegedOperationsCoordinator.shared
/// try await coordinator.installLaunchDaemon(plistPath: path, serviceID: id)
/// ```
@MainActor
final class PrivilegedOperationsCoordinator {

    // MARK: - Singleton

    static let shared = PrivilegedOperationsCoordinator()

    private init() {
        AppLogger.shared.log("🔐 [PrivCoordinator] Initialized with operation mode: \(Self.operationMode)")
    }

    // MARK: - Operation Modes

    enum OperationMode {
        case privilegedHelper  // XPC to root daemon (future: Phase 2)
        case directSudo        // AuthorizationExecuteWithPrivileges (current)
    }

    /// Determine which operation mode to use based on build configuration and helper availability
    static var operationMode: OperationMode {
        #if DEBUG
        // Debug builds always use direct sudo for easy contributor testing
        return .directSudo
        #else
        // Release builds prefer helper if available, fall back to sudo
        // TODO: Phase 2 - Check if helper is installed
        // if HelperManager.shared.isHelperInstalled() {
        //     return .privilegedHelper
        // }
        return .directSudo
        #endif
    }

    // MARK: - Unified Privileged Operations API

    // MARK: LaunchDaemon Operations

    /// Install a LaunchDaemon plist file to /Library/LaunchDaemons/
    func installLaunchDaemon(plistPath: String, serviceID: String) async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Installing LaunchDaemon: \(serviceID)")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallLaunchDaemon(plistPath: plistPath, serviceID: serviceID)
        case .directSudo:
            try await sudoInstallLaunchDaemon(plistPath: plistPath, serviceID: serviceID)
        }
    }

    /// Install all LaunchDaemon services with consolidated single-prompt method
    func installAllLaunchDaemonServices(
        kanataBinaryPath: String,
        kanataConfigPath: String,
        tcpPort: Int
    ) async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Installing all LaunchDaemon services")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallAllServices(
                kanataBinaryPath: kanataBinaryPath,
                kanataConfigPath: kanataConfigPath,
                tcpPort: tcpPort
            )
        case .directSudo:
            try await sudoInstallAllServices(
                kanataBinaryPath: kanataBinaryPath,
                kanataConfigPath: kanataConfigPath,
                tcpPort: tcpPort
            )
        }
    }

    /// Restart unhealthy LaunchDaemon services
    func restartUnhealthyServices() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Restarting unhealthy services")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperRestartServices()
        case .directSudo:
            try await sudoRestartServices()
        }
    }

    /// Regenerate service configuration with current settings
    func regenerateServiceConfiguration() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Regenerating service configuration")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperRegenerateConfig()
        case .directSudo:
            try await sudoRegenerateConfig()
        }
    }

    /// Install log rotation service
    func installLogRotation() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Installing log rotation")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallLogRotation()
        case .directSudo:
            try await sudoInstallLogRotation()
        }
    }

    // MARK: VirtualHID Operations

    /// Activate VirtualHID Manager
    func activateVirtualHIDManager() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Activating VirtualHID Manager")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperActivateVHID()
        case .directSudo:
            try await sudoActivateVHID()
        }
    }

    /// Uninstall all VirtualHID driver versions
    func uninstallVirtualHIDDrivers() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Uninstalling VirtualHID drivers")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperUninstallDrivers()
        case .directSudo:
            try await sudoUninstallDrivers()
        }
    }

    /// Download and install specific VirtualHID driver version
    func installVirtualHIDDriver(version: String, downloadURL: String) async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Installing VirtualHID driver v\(version)")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperInstallDriver(version: version, downloadURL: downloadURL)
        case .directSudo:
            try await sudoInstallDriver(version: version, downloadURL: downloadURL)
        }
    }

    // MARK: Process Management Operations

    /// Terminate a process by PID
    func terminateProcess(pid: Int32) async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Terminating process PID=\(pid)")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperTerminateProcess(pid: pid)
        case .directSudo:
            try await sudoTerminateProcess(pid: pid)
        }
    }

    /// Kill all Kanata processes
    func killAllKanataProcesses() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Killing all Kanata processes")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperKillAllKanata()
        case .directSudo:
            try await sudoKillAllKanata()
        }
    }

    /// Restart Karabiner VirtualHID daemon
    func restartKarabinerDaemon() async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Restarting Karabiner daemon")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperRestartKarabinerDaemon()
        case .directSudo:
            try await sudoRestartKarabinerDaemon()
        }
    }

    // MARK: Generic Execute

    /// Execute a shell command with administrator privileges
    func executeCommand(_ command: String, description: String) async throws {
        AppLogger.shared.log("🔐 [PrivCoordinator] Executing: \(description)")

        switch Self.operationMode {
        case .privilegedHelper:
            try await helperExecuteCommand(command, description: description)
        case .directSudo:
            try await sudoExecuteCommand(command, description: description)
        }
    }

    // MARK: - Privileged Helper Path (Phase 2 - Future Implementation)

    private func helperInstallLaunchDaemon(plistPath: String, serviceID: String) async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperInstallAllServices(
        kanataBinaryPath: String,
        kanataConfigPath: String,
        tcpPort: Int
    ) async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperRestartServices() async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperRegenerateConfig() async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperInstallLogRotation() async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperActivateVHID() async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperUninstallDrivers() async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperInstallDriver(version: String, downloadURL: String) async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperTerminateProcess(pid: Int32) async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperKillAllKanata() async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperRestartKarabinerDaemon() async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    private func helperExecuteCommand(_ command: String, description: String) async throws {
        // TODO: Phase 2 - Implement XPC call to privileged helper
        fatalError("Privileged helper not yet implemented - Phase 2 work")
    }

    // MARK: - Direct Sudo Path (Current Implementation)

    /// Install LaunchDaemon plist using osascript with admin privileges
    private func sudoInstallLaunchDaemon(plistPath: String, serviceID: String) async throws {
        let launchDaemonsPath = "/Library/LaunchDaemons"
        let finalPath = "\(launchDaemonsPath)/\(serviceID).plist"

        let command = """
        mkdir -p '\(launchDaemonsPath)' && \
        cp '\(plistPath)' '\(finalPath)' && \
        chown root:wheel '\(finalPath)' && \
        chmod 644 '\(finalPath)'
        """

        try await sudoExecuteCommand(
            command,
            description: "Install LaunchDaemon: \(serviceID)"
        )
    }

    /// Install all LaunchDaemon services using consolidated single-prompt method
    /// This delegates to LaunchDaemonInstaller which has the complex multi-service logic
    private func sudoInstallAllServices(
        kanataBinaryPath: String,
        kanataConfigPath: String,
        tcpPort: Int
    ) async throws {
        // For now, this delegates to LaunchDaemonInstaller's existing implementation
        // Once we extract all the logic, we'll move it here
        let installer = LaunchDaemonInstaller()
        let success = installer.createConfigureAndLoadAllServices()

        if !success {
            throw PrivilegedOperationError.installationFailed("LaunchDaemon installation failed")
        }
    }

    /// Restart unhealthy services using LaunchDaemonInstaller
    private func sudoRestartServices() async throws {
        let installer = LaunchDaemonInstaller()
        let success = await installer.restartUnhealthyServices()

        if !success {
            throw PrivilegedOperationError.operationFailed("Service restart failed")
        }
    }

    /// Regenerate service configuration using LaunchDaemonInstaller
    private func sudoRegenerateConfig() async throws {
        let installer = LaunchDaemonInstaller()
        let success = await installer.regenerateServiceWithCurrentSettings()

        if !success {
            throw PrivilegedOperationError.operationFailed("Config regeneration failed")
        }
    }

    /// Install log rotation using LaunchDaemonInstaller
    private func sudoInstallLogRotation() async throws {
        let installer = LaunchDaemonInstaller()
        let success = installer.installLogRotationService()

        if !success {
            throw PrivilegedOperationError.operationFailed("Log rotation installation failed")
        }
    }

    /// Activate VirtualHID Manager using VHIDDeviceManager
    private func sudoActivateVHID() async throws {
        let vhidManager = VHIDDeviceManager()
        let success = await vhidManager.activateManager()

        if !success {
            throw PrivilegedOperationError.operationFailed("VirtualHID activation failed")
        }
    }

    /// Uninstall VirtualHID drivers using VHIDDeviceManager
    private func sudoUninstallDrivers() async throws {
        let vhidManager = VHIDDeviceManager()
        let success = await vhidManager.uninstallAllDriverVersions()

        if !success {
            throw PrivilegedOperationError.operationFailed("Driver uninstallation failed")
        }
    }

    /// Install VirtualHID driver using VHIDDeviceManager
    private func sudoInstallDriver(version: String, downloadURL: String) async throws {
        let vhidManager = VHIDDeviceManager()
        let success = await vhidManager.downloadAndInstallCorrectVersion()

        if !success {
            throw PrivilegedOperationError.operationFailed("Driver installation failed")
        }
    }

    /// Terminate a process using kill command with admin privileges
    private func sudoTerminateProcess(pid: Int32) async throws {
        // Try SIGTERM first
        let termCommand = "/bin/kill -TERM \(pid)"

        do {
            try await sudoExecuteCommand(termCommand, description: "Terminate process \(pid)")
        } catch {
            // If SIGTERM fails, try SIGKILL
            AppLogger.shared.log("⚠️ [PrivCoordinator] SIGTERM failed, trying SIGKILL")
            let killCommand = "/bin/kill -9 \(pid)"
            try await sudoExecuteCommand(killCommand, description: "Force kill process \(pid)")
        }
    }

    /// Kill all Kanata processes
    private func sudoKillAllKanata() async throws {
        let command = "/usr/bin/pkill -f kanata"
        try await sudoExecuteCommand(command, description: "Kill all Kanata processes")
    }

    /// Restart Karabiner daemon
    private func sudoRestartKarabinerDaemon() async throws {
        let killCommand = "/usr/bin/pkill -f Karabiner-VirtualHIDDevice-Daemon"
        try await sudoExecuteCommand(killCommand, description: "Restart Karabiner daemon")

        // Wait for daemon to restart
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    }

    /// Execute a shell command with administrator privileges using osascript
    private func sudoExecuteCommand(_ command: String, description: String) async throws {
        let escaped = escapeForAppleScript(command)
        let prompt = "KeyPath needs administrator access to \(description.lowercased())."

        let osascriptCommand = """
        do shell script "\(escaped)" with administrator privileges with prompt "\(prompt)"
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [PrivCoordinator] Successfully executed: \(description)")
            } else {
                AppLogger.shared.log("❌ [PrivCoordinator] Failed to execute: \(description)")
                AppLogger.shared.log("❌ [PrivCoordinator] Output: \(output)")
                throw PrivilegedOperationError.commandFailed(
                    description: description,
                    exitCode: task.terminationStatus,
                    output: output
                )
            }
        } catch let error as PrivilegedOperationError {
            throw error
        } catch {
            AppLogger.shared.log("❌ [PrivCoordinator] Error executing: \(description) - \(error)")
            throw PrivilegedOperationError.executionError(description: description, error: error)
        }
    }

    // MARK: - Helper Methods

    /// Escape a string for use in AppleScript
    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

// MARK: - Error Types

enum PrivilegedOperationError: LocalizedError {
    case installationFailed(String)
    case operationFailed(String)
    case commandFailed(description: String, exitCode: Int32, output: String)
    case executionError(description: String, error: Error)

    var errorDescription: String? {
        switch self {
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        case .commandFailed(let description, let exitCode, let output):
            return "Command failed (\(description)): exit code \(exitCode)\nOutput: \(output)"
        case .executionError(let description, let error):
            return "Execution error (\(description)): \(error.localizedDescription)"
        }
    }
}
