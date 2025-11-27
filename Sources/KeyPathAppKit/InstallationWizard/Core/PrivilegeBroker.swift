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

    // MARK: - LaunchDaemon Operations

    /// Install a LaunchDaemon plist file to /Library/LaunchDaemons/
    public func installLaunchDaemon(plistPath: String, serviceID: String) async throws {
        try await coordinator.installLaunchDaemon(plistPath: plistPath, serviceID: serviceID)
    }

    // MARK: - Service Management

    /// Install all LaunchDaemon services
    public func installAllLaunchDaemonServices() async throws {
        try await coordinator.installAllLaunchDaemonServices()
    }

    /// Restart unhealthy services
    public func restartUnhealthyServices() async throws {
        try await coordinator.restartUnhealthyServices()
    }

    /// Install log rotation service
    public func installLogRotation() async throws {
        try await coordinator.installLogRotation()
    }

    /// Install LaunchDaemon services without loading (adopt/replace paths)
    public func installLaunchDaemonServicesWithoutLoading() async throws {
        try await coordinator.installLaunchDaemonServicesWithoutLoading()
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
    public func stopKanataService() async throws {
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
