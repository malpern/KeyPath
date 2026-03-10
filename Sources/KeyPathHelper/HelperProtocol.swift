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

    /// Restart services that are in an unhealthy state
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func recoverRequiredRuntimeServices(reply: @escaping (Bool, String?) -> Void)

    /// Regenerate and reload service configuration
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func regenerateServiceConfiguration(reply: @escaping (Bool, String?) -> Void)

    /// Install newsyslog config for Kanata log rotation
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func installNewsyslogConfig(reply: @escaping (Bool, String?) -> Void)

    /// Repair VirtualHID daemon services
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func repairVHIDDaemonServices(reply: @escaping (Bool, String?) -> Void)

    /// Install only the privileged services required by the split runtime path.
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func installRequiredRuntimeServices(reply: @escaping (Bool, String?) -> Void)

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
    @available(*, deprecated, message: "Use installBundledVHIDDriver instead - no download needed")
    func downloadAndInstallCorrectVHIDDriver(reply: @escaping (Bool, String?) -> Void)

    /// Install VHID driver from a bundled .pkg file (no download required)
    /// - Parameters:
    ///   - pkgPath: Path to the bundled .pkg file in the app bundle
    ///   - reply: Completion handler with (success, errorMessage)
    func installBundledVHIDDriver(pkgPath: String, reply: @escaping (Bool, String?) -> Void)

    /// Probe whether root-side pqrs VirtualHID output access is available for a future split runtime.
    /// - Parameter reply: Completion handler with
    ///   - payload: JSON-encoded `KanataOutputBridgeStatus`
    ///   - errorMessage: failure details, if any
    func getKanataOutputBridgeStatus(
        reply: @escaping (String?, String?) -> Void
    )

    /// Prepare a privileged output-bridge session for a future split runtime.
    /// - Parameters:
    ///   - hostPID: PID of the bundled user-session runtime that will connect
    ///   - reply: Completion handler with
    ///   - payload: JSON-encoded `KanataOutputBridgeSession`
    ///   - errorMessage: failure details, if any
    func prepareKanataOutputBridgeSession(
        hostPID: Int32,
        reply: @escaping (String?, String?) -> Void
    )

    /// Activate a prepared privileged output-bridge session and ensure the dedicated companion binds its socket.
    /// - Parameters:
    ///   - sessionID: session identifier returned by prepare
    ///   - reply: Completion handler with (success, errorMessage)
    func activateKanataOutputBridgeSession(
        sessionID: String,
        reply: @escaping (Bool, String?) -> Void
    )

    /// Restart the dedicated output-bridge companion and ensure it is relaunched cleanly.
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func restartKanataOutputBridgeCompanion(
        reply: @escaping (Bool, String?) -> Void
    )

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

    /// Karabiner conflict management
    func disableKarabinerGrabber(reply: @escaping (Bool, String?) -> Void)

    // Note: executeCommand removed for security reasons.
    // All privileged operations must be explicitly defined with proper validation.
    // Arbitrary shell command execution creates too broad an attack surface.

    // MARK: - Bundled Kanata Installation

    /// Install only the bundled kanata binary to the system location (/Library/KeyPath/bin/kanata)
    /// - Parameter reply: Completion handler with (success, errorMessage)
    func installBundledKanataBinaryOnly(reply: @escaping (Bool, String?) -> Void)

    // MARK: - Uninstall Operations

    /// Uninstall KeyPath completely, removing all services, binaries, and optionally user config
    /// - Parameters:
    ///   - deleteConfig: If true, also removes user configuration at ~/.config/keypath
    ///   - reply: Completion handler with (success, errorMessage)
    func uninstallKeyPath(deleteConfig: Bool, reply: @escaping (Bool, String?) -> Void)
}
