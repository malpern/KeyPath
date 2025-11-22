import Foundation

/// XPC protocol for privileged operations performed by KeyPathHelper
///
/// This protocol defines the interface between KeyPath.app and the privileged helper tool.
/// All operations require root privileges and are executed via XPC communication.
///
/// **Security:** Only connections from KeyPath.app (com.keypath.app) are accepted.
/// The helper validates the caller's code signature before accepting connections.
///
/// **Note:** This protocol is duplicated in both KeyPath and KeyPathHelper targets.
/// Any changes must be synchronized between both copies.
@objc protocol HelperProtocol {
    // MARK: - Version Management

    /// Get the helper version
    /// - Parameter reply: Completion handler with (version string, errorMessage)
    func getVersion(reply: @escaping (String?, String?) -> Void)

    // MARK: - LaunchDaemon Operations

    /// Install a single LaunchDaemon service
    /// - Parameters:
    ///   - plistPath: Path to the plist file to install
    ///   - serviceID: Service identifier (e.g., "com.keypath.kanata")
    ///   - reply: Completion handler with (success, errorMessage)
    func installLaunchDaemon(
        plistPath: String, serviceID: String, reply: @escaping (Bool, String?) -> Void
    )

    /// Restart services that are in an unhealthy state
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func restartUnhealthyServices(reply: @escaping (Bool, String?) -> Void)

    /// Regenerate and reload service configuration
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func regenerateServiceConfiguration(reply: @escaping (Bool, String?) -> Void)

    /// Install log rotation service for Kanata logs
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func installLogRotation(reply: @escaping (Bool, String?) -> Void)

    /// Repair VirtualHID daemon services
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func repairVHIDDaemonServices(reply: @escaping (Bool, String?) -> Void)

    /// Install LaunchDaemon services without loading them
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func installLaunchDaemonServicesWithoutLoading(reply: @escaping (Bool, String?) -> Void)

    // MARK: - VirtualHID Operations

    /// Activate the VirtualHID Manager service
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func activateVirtualHIDManager(reply: @escaping (Bool, String?) -> Void)

    /// Uninstall all versions of VirtualHID drivers
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func uninstallVirtualHIDDrivers(reply: @escaping (Bool, String?) -> Void)

    /// Install a specific version of VirtualHID driver
    /// - Parameters:
    ///   - version: Driver version to install (e.g., "5.0.0")
    ///   - downloadURL: URL to download the driver from
    ///   - reply: Completion handler with (success, errorMessage)
    func installVirtualHIDDriver(
        version: String, downloadURL: String, reply: @escaping (Bool, String?) -> Void
    )

    /// Detect system requirements and install the correct VHID driver version
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func downloadAndInstallCorrectVHIDDriver(reply: @escaping (Bool, String?) -> Void)

    // MARK: - Process Management

    /// Terminate a specific process by PID
    /// - Parameters:
    ///   - pid: Process ID to terminate
    ///   - reply: Completion handler with (success, errorMessage)
    func terminateProcess(_ pid: Int32, reply: @escaping (Bool, String?) -> Void)

    /// Kill all running Kanata processes
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func killAllKanataProcesses(reply: @escaping (Bool, String?) -> Void)

    /// Restart the Karabiner daemon
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func restartKarabinerDaemon(reply: @escaping (Bool, String?) -> Void)

    // Karabiner conflict management
    func disableKarabinerGrabber(reply: @escaping (Bool, String?) -> Void)

    // Note: executeCommand removed for security reasons.
    // All privileged operations must be explicitly defined with proper validation.
    // Arbitrary shell command execution creates too broad an attack surface.

    // MARK: - Bundled Kanata Installation

    /// Install only the bundled kanata binary to the system location (/Library/KeyPath/bin/kanata)
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func installBundledKanataBinaryOnly(reply: @escaping (Bool, String?) -> Void)
}
