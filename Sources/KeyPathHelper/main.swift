import Foundation
import os
import Security

// KeyPath Privileged Helper
//
// This helper tool runs as root and provides privileged operations to KeyPath.app
// via XPC communication. It is registered via SMAppService and runs on-demand
// as a LaunchDaemon Mach service.
//
// Security:
// - Only accepts connections from KeyPath.app (com.keypath.KeyPath) in release builds
// - Validates code signature via audit token before accepting connections
// - All operations are logged to system log for audit trail

// MARK: - Security Validation

/// Validates an XPC connection using the caller's process ID
/// - Parameters:
///   - connection: The XPC connection to validate
///   - requirement: The code signature requirement string
/// - Returns: true if the connection is from a valid, authorized caller
func validateConnection(_ connection: NSXPCConnection, requirement requirementString: String)
    -> Bool {
    let logger = Logger(subsystem: "com.keypath.helper", category: "xpc")
    // Get the process ID from the connection
    let pid = connection.processIdentifier

    // Create attributes dictionary for the guest code object using PID
    let attributes: [CFString: Any] = [
        kSecGuestAttributePid: pid
    ]

    // Get the code object for the connecting process
    var code: SecCode?
    var status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code)

    guard status == errSecSuccess, let validCode = code else {
        NSLog("[KeyPathHelper] Failed to get code object for PID \(pid): \(status)")
        logger.error(
            "Failed to get code object for PID \(pid, privacy: .public): status \(status, privacy: .public)"
        )
        return false
    }

    // Create the requirement
    var requirement: SecRequirement?
    status = SecRequirementCreateWithString(requirementString as CFString, [], &requirement)

    guard status == errSecSuccess, let validRequirement = requirement else {
        NSLog("[KeyPathHelper] Failed to create requirement: \(status)")
        logger.error("Failed to create requirement: status \(status, privacy: .public)")
        return false
    }

    // Validate the code against the requirement
    status = SecCodeCheckValidity(validCode, [], validRequirement)

    if status == errSecSuccess {
        NSLog("[KeyPathHelper] Code signature validation passed for PID \(pid)")
        logger.info("Code signature validation passed for PID \(pid, privacy: .public)")
        return true
    } else {
        // Get the actual identifier of the connecting process for debugging
        var staticCode: SecStaticCode?
        var codeInfo: CFDictionary?
        if SecCodeCopyStaticCode(validCode, [], &staticCode) == errSecSuccess,
           let sc = staticCode,
           SecCodeCopySigningInformation(sc, [], &codeInfo) == errSecSuccess,
           let info = codeInfo as? [String: Any] {
            let identifier = info[kSecCodeInfoIdentifier as String] as? String ?? "unknown"
            let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String ?? "unknown"
            NSLog("[KeyPathHelper] Code signature validation failed for PID \(pid): \(status)")
            NSLog("[KeyPathHelper]   → Connecting process: identifier=\(identifier), team=\(teamID)")
            NSLog("[KeyPathHelper]   → Expected: identifier=\"com.keypath.KeyPath\", team=\"X2RKZ5TG99\"")
            NSLog("[KeyPathHelper]   → This likely means app was updated but not restarted")
            logger.error(
                """
                Code signature validation failed for PID \(pid, privacy: .public): \
                status \(status, privacy: .public), identifier=\(identifier, privacy: .public), \
                team=\(teamID, privacy: .public)
                """
            )
        } else {
            NSLog("[KeyPathHelper] Code signature validation failed for PID \(pid): \(status)")
            logger.error(
                "Code signature validation failed for PID \(pid, privacy: .public): status \(status, privacy: .public)"
            )
        }
        return false
    }
}

/// Delegate for the XPC listener
class HelperDelegate: NSObject, NSXPCListenerDelegate {
    /// Handle incoming XPC connections
    /// - Parameters:
    ///   - listener: The XPC listener receiving the connection
    ///   - connection: The new connection to validate and accept
    /// - Returns: true if the connection should be accepted, false otherwise
    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Security requirement:
        // - DEBUG: allow any app from our Developer ID team for contributor convenience
        // - RELEASE: require the exact app bundle identifier for strict production security
        #if DEBUG
            let requirementString =
                "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = X2RKZ5TG99"
        #else
            // swiftlint:disable:next line_length
            let requirementString = "identifier \"com.keypath.KeyPath\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = X2RKZ5TG99"
        #endif

        // Validate the caller's code signature using audit token
        guard validateConnection(connection, requirement: requirementString) else {
            NSLog("[KeyPathHelper] ❌ Connection rejected: signature validation failed")
            return false
        }

        NSLog("[KeyPathHelper] ✅ Accepting connection from validated KeyPath.app")

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
    let logger = Logger(subsystem: "com.keypath.helper", category: "lifecycle")
    NSLog("[KeyPathHelper] Starting privileged helper (version 1.1.0)")
    logger.info("Starting privileged helper (v1.1.0)")

    // Create the XPC listener on the Mach service
    let delegate = HelperDelegate()
    let listener = NSXPCListener(machServiceName: "com.keypath.helper")
    listener.delegate = delegate

    // Start the listener (blocks until the helper is terminated)
    NSLog("[KeyPathHelper] Listening for XPC connections on com.keypath.helper")
    logger.info("Listening for XPC connections on com.keypath.helper")
    listener.resume()

    // Run the runloop indefinitely
    RunLoop.current.run()
}

// Start the helper
main()
