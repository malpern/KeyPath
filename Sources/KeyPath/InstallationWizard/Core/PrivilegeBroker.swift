import Foundation

/// Strategy object for executing privileged commands
/// Wraps PrivilegedOperationsCoordinator to provide a simple interface for the façade
/// Start with concrete type - add protocol if we need test doubles later
@MainActor
public struct PrivilegeBroker: Sendable {
    /// Coordinator instance (singleton)
    private let coordinator: PrivilegedOperationsCoordinator
    
    /// Create a broker using the shared coordinator
    init(coordinator: PrivilegedOperationsCoordinator? = nil) {
        // Use provided coordinator or get shared instance
        self.coordinator = coordinator ?? PrivilegedOperationsCoordinator.shared
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
    
    // MARK: - Component Installation
    
    /// Download and install correct VHID driver
    public func downloadAndInstallCorrectVHIDDriver() async throws {
        try await coordinator.downloadAndInstallCorrectVHIDDriver()
    }
    
    /// Repair VHID daemon services
    public func repairVHIDDaemonServices() async throws {
        try await coordinator.repairVHIDDaemonServices()
    }
}

