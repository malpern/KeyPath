import Foundation

/// Implementation of privileged operations for KeyPath
///
/// This service runs as root and executes privileged operations requested by KeyPath.app.
/// All operations are logged to the system log for audit purposes.
class HelperService: NSObject, HelperProtocol {

    // MARK: - Constants

    /// Helper version (must match app version for compatibility)
    private static let version = "1.0.0"

    // MARK: - Version Management

    func getVersion(reply: @escaping (String?, String?) -> Void) {
        NSLog("[KeyPathHelper] getVersion requested")
        reply(Self.version, nil)
    }

    // MARK: - LaunchDaemon Operations

    func installLaunchDaemon(plistPath: String, serviceID: String, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installLaunchDaemon requested: \(serviceID)")
        executePrivilegedOperation(
            name: "installLaunchDaemon",
            operation: {
                // TODO: Implement LaunchDaemon installation
                // Copy plistPath to /Library/LaunchDaemons/\(serviceID).plist
                throw HelperError.notImplemented("installLaunchDaemon")
            },
            reply: reply
        )
    }

    func installAllLaunchDaemonServices(kanataBinaryPath: String, kanataConfigPath: String, tcpPort: Int, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installAllLaunchDaemonServices requested (binary: \(kanataBinaryPath), port: \(tcpPort))")
        executePrivilegedOperation(
            name: "installAllLaunchDaemonServices",
            operation: {
                // TODO: Implement installation of all LaunchDaemon services
                // Kanata, VHID Manager, VHID Daemon, etc.
                throw HelperError.notImplemented("installAllLaunchDaemonServices")
            },
            reply: reply
        )
    }

    func installAllLaunchDaemonServicesWithPreferences(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installAllLaunchDaemonServicesWithPreferences requested")
        executePrivilegedOperation(
            name: "installAllLaunchDaemonServicesWithPreferences",
            operation: {
                // TODO: Implement installation using preferences
                throw HelperError.notImplemented("installAllLaunchDaemonServicesWithPreferences")
            },
            reply: reply
        )
    }

    func restartUnhealthyServices(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] restartUnhealthyServices requested")
        executePrivilegedOperation(
            name: "restartUnhealthyServices",
            operation: {
                // TODO: Implement service health checking and restart
                throw HelperError.notImplemented("restartUnhealthyServices")
            },
            reply: reply
        )
    }

    func regenerateServiceConfiguration(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] regenerateServiceConfiguration requested")
        executePrivilegedOperation(
            name: "regenerateServiceConfiguration",
            operation: {
                // TODO: Implement service configuration regeneration
                throw HelperError.notImplemented("regenerateServiceConfiguration")
            },
            reply: reply
        )
    }

    func installLogRotation(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installLogRotation requested")
        executePrivilegedOperation(
            name: "installLogRotation",
            operation: {
                // TODO: Implement log rotation service installation
                throw HelperError.notImplemented("installLogRotation")
            },
            reply: reply
        )
    }

    func repairVHIDDaemonServices(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] repairVHIDDaemonServices requested")
        executePrivilegedOperation(
            name: "repairVHIDDaemonServices",
            operation: {
                // TODO: Implement VHID daemon repair
                throw HelperError.notImplemented("repairVHIDDaemonServices")
            },
            reply: reply
        )
    }

    func installLaunchDaemonServicesWithoutLoading(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installLaunchDaemonServicesWithoutLoading requested")
        executePrivilegedOperation(
            name: "installLaunchDaemonServicesWithoutLoading",
            operation: {
                // TODO: Implement LaunchDaemon installation without loading
                throw HelperError.notImplemented("installLaunchDaemonServicesWithoutLoading")
            },
            reply: reply
        )
    }

    // MARK: - VirtualHID Operations

    func activateVirtualHIDManager(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] activateVirtualHIDManager requested")
        executePrivilegedOperation(
            name: "activateVirtualHIDManager",
            operation: {
                // TODO: Implement VHID Manager activation
                throw HelperError.notImplemented("activateVirtualHIDManager")
            },
            reply: reply
        )
    }

    func uninstallVirtualHIDDrivers(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] uninstallVirtualHIDDrivers requested")
        executePrivilegedOperation(
            name: "uninstallVirtualHIDDrivers",
            operation: {
                // TODO: Implement VHID driver uninstallation
                throw HelperError.notImplemented("uninstallVirtualHIDDrivers")
            },
            reply: reply
        )
    }

    func installVirtualHIDDriver(version: String, downloadURL: String, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] installVirtualHIDDriver requested: v\(version) from \(downloadURL)")
        executePrivilegedOperation(
            name: "installVirtualHIDDriver",
            operation: {
                // TODO: Implement VHID driver installation
                throw HelperError.notImplemented("installVirtualHIDDriver")
            },
            reply: reply
        )
    }

    func downloadAndInstallCorrectVHIDDriver(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] downloadAndInstallCorrectVHIDDriver requested")
        executePrivilegedOperation(
            name: "downloadAndInstallCorrectVHIDDriver",
            operation: {
                // TODO: Implement auto-detection and installation of correct VHID driver
                throw HelperError.notImplemented("downloadAndInstallCorrectVHIDDriver")
            },
            reply: reply
        )
    }

    // MARK: - Process Management

    func terminateProcess(_ pid: Int32, reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] terminateProcess(\(pid)) requested")
        executePrivilegedOperation(
            name: "terminateProcess",
            operation: {
                // Implement process termination
                let result = kill(pid, SIGTERM)
                if result != 0 {
                    throw HelperError.operationFailed("Failed to terminate process \(pid): \(String(cString: strerror(errno)))")
                }
                NSLog("[KeyPathHelper] Successfully terminated process \(pid)")
            },
            reply: reply
        )
    }

    func killAllKanataProcesses(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] killAllKanataProcesses requested")
        executePrivilegedOperation(
            name: "killAllKanataProcesses",
            operation: {
                // TODO: Implement killing all Kanata processes
                throw HelperError.notImplemented("killAllKanataProcesses")
            },
            reply: reply
        )
    }

    func restartKarabinerDaemon(reply: @escaping (Bool, String?) -> Void) {
        NSLog("[KeyPathHelper] restartKarabinerDaemon requested")
        executePrivilegedOperation(
            name: "restartKarabinerDaemon",
            operation: {
                // TODO: Implement Karabiner daemon restart
                throw HelperError.notImplemented("restartKarabinerDaemon")
            },
            reply: reply
        )
    }

    // Note: executeCommand removed for security. Use explicit operations only.

    // MARK: - Helper Methods

    /// Execute a privileged operation with error handling
    /// - Parameters:
    ///   - name: Operation name for logging
    ///   - operation: The operation to execute (can throw)
    ///   - reply: Completion handler to call with result
    private func executePrivilegedOperation(
        name: String,
        operation: () throws -> Void,
        reply: @escaping (Bool, String?) -> Void
    ) {
        do {
            try operation()
            NSLog("[KeyPathHelper] ✅ \(name) succeeded")
            reply(true, nil)
        } catch let error as HelperError {
            NSLog("[KeyPathHelper] ❌ \(name) failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        } catch {
            NSLog("[KeyPathHelper] ❌ \(name) failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
    }
}

// MARK: - Error Types

/// Errors that can occur during privileged operations
enum HelperError: Error, LocalizedError {
    case notImplemented(String)
    case operationFailed(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let operation):
            return "Operation not yet implemented: \(operation)"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        case .invalidArgument(let reason):
            return "Invalid argument: \(reason)"
        }
    }
}
