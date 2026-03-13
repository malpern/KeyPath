import Foundation
import KeyPathWizardCore

/// Strategy object for executing privileged commands.
/// Wraps `WizardPrivilegedOperating` to give the InstallerEngine a stable surface.
/// Start with concrete type; add a protocol only if we need test doubles later.
@MainActor
public struct PrivilegeBroker {
    enum BrokerError: Error {
        case coordinatorNotConfigured
    }

    /// Coordinator instance (via WizardDependencies)
    private let coordinator: (any WizardPrivilegedOperating)?

    /// Create a broker using the WizardDependencies coordinator
    public init() {
        coordinator = WizardDependencies.privilegedOperations
    }

    /// Internal initializer for tests that need custom coordinators
    init(coordinator: any WizardPrivilegedOperating) {
        self.coordinator = coordinator
    }

    private func requireCoordinator() throws -> any WizardPrivilegedOperating {
        guard let c = coordinator else { throw BrokerError.coordinatorNotConfigured }
        return c
    }

    // MARK: - Service Management

    /// Install only the privileged services required by the split runtime path.
    public func installRequiredRuntimeServices() async throws {
        try await requireCoordinator().installRequiredRuntimeServices()
    }

    /// Restart unhealthy services
    public func recoverRequiredRuntimeServices() async throws {
        try await requireCoordinator().recoverRequiredRuntimeServices()
    }

    /// Install newsyslog config for log rotation
    public func installNewsyslogConfig() async throws {
        try await requireCoordinator().installNewsyslogConfig()
    }

    /// Regenerate service configuration (TCP/plist refresh)
    public func regenerateServiceConfiguration() async throws {
        try await requireCoordinator().regenerateServiceConfiguration()
    }

    /// Repair VHID daemon services
    public func repairVHIDDaemonServices() async throws {
        try await requireCoordinator().repairVHIDDaemonServices()
    }

    // MARK: - Component Installation

    /// Download and install correct VHID driver
    public func downloadAndInstallCorrectVHIDDriver() async throws {
        try await requireCoordinator().downloadAndInstallCorrectVHIDDriver()
    }

    /// Activate VirtualHID Manager
    public func activateVirtualHIDManager() async throws {
        try await requireCoordinator().activateVirtualHIDManager()
    }

    /// Terminate a process by PID
    public func terminateProcess(pid: Int32) async throws {
        try await requireCoordinator().terminateProcess(pid: pid)
    }

    /// Kill all Kanata processes
    public func killAllKanataProcesses() async throws {
        try await requireCoordinator().killAllKanataProcesses()
    }

    /// Stop Kanata LaunchDaemon and kill any remaining processes
    public func stopRecoveryDaemonService() async throws {
        let c = try requireCoordinator()
        let serviceID = WizardDependencies.daemonManager?.kanataServiceID ?? "com.keypath.kanata"
        let cmd = "/bin/launchctl bootout system/\(serviceID) 2>/dev/null || true"
        try await c.sudoExecuteCommand(cmd, description: "Stop Kanata service")
        try await c.killAllKanataProcesses()
    }

    /// Restart Karabiner daemon with verification
    public func restartKarabinerDaemonVerified() async throws -> Bool {
        try await requireCoordinator().restartKarabinerDaemonVerified()
    }

    /// Uninstall VirtualHID drivers (removes VHID daemon plists)
    public func uninstallVirtualHIDDrivers() async throws {
        try await requireCoordinator().uninstallVirtualHIDDrivers()
    }

    /// Disable Karabiner grabber (stops conflicting processes)
    public func disableKarabinerGrabber() async throws {
        try await requireCoordinator().disableKarabinerGrabber()
    }

    /// Execute a privileged command via sudo/osascript
    public func sudoExecuteCommand(_ command: String, description: String) async throws {
        try await requireCoordinator().sudoExecuteCommand(command, description: description)
    }
}
