import Foundation

/// Strategy object for executing privileged commands.
/// Wraps `PrivilegedOperationsCoordinator` to give the InstallerEngine a stable surface.
/// Start with concrete type; add a protocol only if we need test doubles later.
@MainActor
public struct PrivilegeBroker {
    /// Coordinator instance (singleton)
    private let coordinator: PrivilegedOperationsCoordinating

    /// Create a broker using the shared coordinator
    public init() {
        coordinator = PrivilegedOperationsCoordinator.shared
    }

    /// Internal initializer for tests that need custom coordinators
    init(coordinator: PrivilegedOperationsCoordinating) {
        self.coordinator = coordinator
    }

    // MARK: - Service Management

    /// Install only the privileged services required by the split runtime path.
    public func installRequiredRuntimeServices() async throws {
        try await coordinator.installRequiredRuntimeServices()
    }

    /// Restart unhealthy services
    public func recoverRequiredRuntimeServices() async throws {
        try await coordinator.recoverRequiredRuntimeServices()
    }

    /// Install newsyslog config for log rotation
    public func installNewsyslogConfig() async throws {
        try await coordinator.installNewsyslogConfig()
    }

    /// Regenerate service configuration (TCP/plist refresh)
    public func regenerateServiceConfiguration() async throws {
        try await coordinator.regenerateServiceConfiguration()
    }

    /// Repair VHID daemon services
    public func repairVHIDDaemonServices() async throws {
        try await coordinator.repairVHIDDaemonServices()
    }

    // MARK: - Component Installation

    /// Download and install correct VHID driver
    public func downloadAndInstallCorrectVHIDDriver() async throws {
        try await coordinator.downloadAndInstallCorrectVHIDDriver()
    }

    /// Install bundled Kanata binary
    public func installBundledKanata() async throws {
        try await coordinator.installBundledKanata()
    }

    /// Activate VirtualHID Manager
    public func activateVirtualHIDManager() async throws {
        try await coordinator.activateVirtualHIDManager()
    }

    /// Terminate a process by PID
    public func terminateProcess(pid: Int32) async throws {
        try await coordinator.terminateProcess(pid: pid)
    }

    /// Kill all Kanata processes
    public func killAllKanataProcesses() async throws {
        try await coordinator.killAllKanataProcesses()
    }

    /// Stop Kanata LaunchDaemon and kill any remaining processes
    public func stopRecoveryDaemonService() async throws {
        let cmd = "/bin/launchctl bootout system/\(KanataDaemonManager.kanataServiceID) 2>/dev/null || true"
        try await coordinator.sudoExecuteCommand(cmd, description: "Stop Kanata service")
        try await coordinator.killAllKanataProcesses()
    }

    /// Restart Karabiner daemon with verification
    public func restartKarabinerDaemonVerified() async throws -> Bool {
        try await coordinator.restartKarabinerDaemonVerified()
    }

    /// Uninstall VirtualHID drivers (removes VHID daemon plists)
    public func uninstallVirtualHIDDrivers() async throws {
        try await coordinator.uninstallVirtualHIDDrivers()
    }

    /// Disable Karabiner grabber (stops conflicting processes)
    public func disableKarabinerGrabber() async throws {
        try await coordinator.disableKarabinerGrabber()
    }

    /// Execute a privileged command via sudo/osascript
    public func sudoExecuteCommand(_ command: String, description: String) async throws {
        try await coordinator.sudoExecuteCommand(command, description: description)
    }
}
