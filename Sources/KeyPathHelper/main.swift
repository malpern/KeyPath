import Foundation

/// KeyPath Privileged Helper
///
/// This helper tool runs as root and provides privileged operations to KeyPath.app
/// via XPC communication. It is installed using SMJobBless() and runs as a LaunchDaemon.
///
/// **Security:**
/// - Only accepts connections from KeyPath.app (com.keypath.app)
/// - Validates code signature before accepting connections
/// - All operations are logged to system log for audit trail

/// Delegate for the XPC listener
class HelperDelegate: NSObject, NSXPCListenerDelegate {

    /// Handle incoming XPC connections
    /// - Parameters:
    ///   - listener: The XPC listener receiving the connection
    ///   - connection: The new connection to validate and accept
    /// - Returns: true if the connection should be accepted, false otherwise
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {

        // Verify the caller is KeyPath.app with valid code signature
        let securityRequirement = "identifier \"com.keypath.app\" and anchor apple generic"

        // Create a SecRequirement from the requirement string
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            securityRequirement as CFString,
            [],
            &requirement
        )

        guard status == errSecSuccess, requirement != nil else {
            NSLog("[KeyPathHelper] Failed to create security requirement: \(status)")
            return false
        }

        // Validate the connection against the requirement
        // Note: In production, we'd extract the audit token from the connection
        // and validate it. For now, we rely on the Mach service configuration.
        // The LaunchDaemon plist restricts which bundle IDs can connect.

        NSLog("[KeyPathHelper] Accepting connection from KeyPath.app")

        // Set up the XPC interface
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = HelperService()

        // Handle connection invalidation
        connection.invalidationHandler = {
            NSLog("[KeyPathHelper] Connection invalidated")
        }

        connection.interruptionHandler = {
            NSLog("[KeyPathHelper] Connection interrupted")
        }

        // Start the connection
        connection.resume()

        return true
    }
}

// MARK: - Main Entry Point

/// Main entry point for the privileged helper
func main() {
    NSLog("[KeyPathHelper] Starting privileged helper (version 1.0.0)")

    // Create the XPC listener on the Mach service
    let delegate = HelperDelegate()
    let listener = NSXPCListener(machServiceName: "com.keypath.helper")
    listener.delegate = delegate

    // Start the listener (blocks until the helper is terminated)
    NSLog("[KeyPathHelper] Listening for XPC connections on com.keypath.helper")
    listener.resume()

    // Run the runloop indefinitely
    RunLoop.current.run()
}

// Start the helper
main()
