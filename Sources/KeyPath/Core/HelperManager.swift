import Foundation
import ServiceManagement

/// Manager for XPC communication with the privileged helper
///
/// This manager handles the XPC connection lifecycle and provides async/await wrappers
/// around the helper's XPC protocol methods.
///
/// **Architecture:**
/// - Singleton pattern for app-wide access
/// - Lazy connection establishment
/// - Automatic reconnection on interruption
/// - Thread-safe connection management
@MainActor
class HelperManager {

    // MARK: - Singleton

    static let shared = HelperManager()

    // MARK: - Properties

    /// XPC connection to the privileged helper
    private var connection: NSXPCConnection?

    /// Mach service name for the helper
    private let helperMachServiceName = "com.keypath.helper"

    /// Bundle identifier for the helper
    private let helperBundleIdentifier = "com.keypath.helper"

    /// Expected helper version (should match HelperService.version)
    private let expectedHelperVersion = "1.0.0"

    /// Cached helper version (lazy loaded)
    private var cachedHelperVersion: String?

    // MARK: - Initialization

    private init() {
        AppLogger.shared.log("🔧 [HelperManager] Initialized")
    }

    nonisolated deinit {
        // Note: Cannot safely access MainActor-isolated connection from deinit
        // Connection will be invalidated when the XPC connection is deallocated
    }

    // MARK: - Connection Management

    /// Get or create the XPC connection to the helper
    /// - Returns: The active XPC connection
    /// - Throws: HelperError if connection cannot be established
    private func getConnection() throws -> NSXPCConnection {
        // Return existing connection if still valid
        if let connection = connection {
            return connection
        }

        // Create new connection
        AppLogger.shared.log("🔗 [HelperManager] Creating XPC connection to \(helperMachServiceName)")

        let newConnection = NSXPCConnection(machServiceName: helperMachServiceName, options: .privileged)

        // Set up the interface
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        // Handle connection lifecycle
        newConnection.invalidationHandler = { [weak self] in
            AppLogger.shared.log("❌ [HelperManager] XPC connection invalidated")
            Task { @MainActor in
                self?.connection = nil
            }
        }

        newConnection.interruptionHandler = { [weak self] in
            AppLogger.shared.log("⚠️ [HelperManager] XPC connection interrupted - will reconnect")
            Task { @MainActor in
                self?.connection = nil
            }
        }

        // Start the connection
        newConnection.resume()

        self.connection = newConnection
        AppLogger.shared.log("✅ [HelperManager] XPC connection established")

        return newConnection
    }

    /// Close the XPC connection
    func disconnect() {
        AppLogger.shared.log("🔌 [HelperManager] Disconnecting XPC connection")
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Helper Status

    /// Check if the privileged helper is installed and registered
    /// - Returns: true if helper is installed, false otherwise
    nonisolated func isHelperInstalled() -> Bool {
        // Check if the helper is registered with SMJobBless
        // This is a simplified check - in production we'd verify version and signature
        let url = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(helperBundleIdentifier)")
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Get the version of the installed helper
    /// - Returns: Version string, or nil if helper not installed or version check fails
    func getHelperVersion() async -> String? {
        // Return cached version if available
        if let cached = cachedHelperVersion {
            return cached
        }

        // Query version from helper
        guard isHelperInstalled() else {
            AppLogger.shared.log("⚠️ [HelperManager] Helper not installed, cannot get version")
            return nil
        }

        do {
            let proxy = try getRemoteProxy()

            return await withCheckedContinuation { continuation in
                proxy.getVersion { version, error in
                    if let version = version {
                        AppLogger.shared.log("✅ [HelperManager] Helper version: \(version)")
                        Task { @MainActor in
                            self.cachedHelperVersion = version
                        }
                        continuation.resume(returning: version)
                    } else {
                        let errorMsg = error ?? "Unknown error"
                        AppLogger.shared.log("❌ [HelperManager] Failed to get helper version: \(errorMsg)")
                        continuation.resume(returning: nil)
                    }
                }
            }
        } catch {
            AppLogger.shared.log("❌ [HelperManager] Failed to connect to helper for version check: \(error)")
            return nil
        }
    }

    /// Check if the helper version matches the expected version
    /// - Returns: true if versions match, false otherwise
    func isHelperVersionCompatible() async -> Bool {
        guard let helperVersion = await getHelperVersion() else {
            return false
        }

        let compatible = helperVersion == expectedHelperVersion
        if !compatible {
            AppLogger.shared.log("⚠️ [HelperManager] Version mismatch - expected: \(expectedHelperVersion), got: \(helperVersion)")
        }
        return compatible
    }

    /// Check if helper needs upgrade (installed but wrong version)
    /// - Returns: true if upgrade needed, false otherwise
    func needsHelperUpgrade() async -> Bool {
        guard isHelperInstalled() else {
            return false  // Not installed, not an upgrade case
        }

        return !(await isHelperVersionCompatible())
    }

    // MARK: - Helper Installation

    /// Install the privileged helper using SMJobBless
    /// - Throws: HelperManagerError if installation fails
    func installHelper() async throws {
        AppLogger.shared.log("🔧 [HelperManager] Installing privileged helper")

        // SMJobBless must be called from the main thread
        return try await withCheckedThrowingContinuation { continuation in
            var authRef: AuthorizationRef?

            // Create authorization reference
            let authStatus = AuthorizationCreate(
                nil,
                nil,
                [.interactionAllowed, .extendRights, .preAuthorize],
                &authRef
            )

            guard authStatus == errAuthorizationSuccess, let authRef = authRef else {
                AppLogger.shared.log("❌ [HelperManager] Failed to create authorization")
                continuation.resume(throwing: HelperManagerError.installationFailed("Authorization failed"))
                return
            }

            // Install the helper using SMJobBless
            var error: Unmanaged<CFError>?
            let success = SMJobBless(
                kSMDomainSystemLaunchd,
                helperBundleIdentifier as CFString,
                authRef,
                &error
            )

            // Free the authorization
            AuthorizationFree(authRef, [])

            if success {
                AppLogger.shared.log("✅ [HelperManager] Privileged helper installed successfully")
                continuation.resume()
            } else {
                let errorDescription = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
                AppLogger.shared.log("❌ [HelperManager] Failed to install helper: \(errorDescription)")
                continuation.resume(throwing: HelperManagerError.installationFailed(errorDescription))
            }
        }
    }

    /// Uninstall the privileged helper
    /// - Throws: HelperManagerError if uninstallation fails
    func uninstallHelper() async throws {
        AppLogger.shared.log("🗑️ [HelperManager] Uninstalling privileged helper")

        // Use launchctl to unload and remove the helper
        let unloadCommand = "sudo launchctl unload /Library/LaunchDaemons/\(helperBundleIdentifier).plist"
        let removeCommand = "sudo rm -f /Library/LaunchDaemons/\(helperBundleIdentifier).plist /Library/PrivilegedHelperTools/\(helperBundleIdentifier)"

        // This would need proper authorization - for now, just a placeholder
        // In production, this would use executeCommand or a similar mechanism
        AppLogger.shared.log("⚠️ [HelperManager] Helper uninstall not yet implemented")
        throw HelperManagerError.operationFailed("Helper uninstall not yet implemented")
    }

    // MARK: - XPC Protocol Wrappers

    /// Get the remote object proxy with proper error handling
    /// - Returns: The remote object proxy conforming to HelperProtocol
    /// - Throws: HelperError if connection fails
    private func getRemoteProxy() throws -> HelperProtocol {
        let connection = try getConnection()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            AppLogger.shared.log("❌ [HelperManager] XPC proxy error: \(error.localizedDescription)")
        }) as? HelperProtocol else {
            throw HelperManagerError.connectionFailed("Failed to create remote proxy")
        }

        return proxy
    }

    /// Execute an XPC call with async/await conversion
    /// - Parameters:
    ///   - name: Operation name for logging
    ///   - call: The XPC call to execute
    /// - Throws: HelperError if the operation fails
    private func executeXPCCall(
        _ name: String,
        _ call: @escaping (HelperProtocol, @escaping (Bool, String?) -> Void) -> Void
    ) async throws {
        AppLogger.shared.log("📤 [HelperManager] Calling \(name)")

        let proxy = try getRemoteProxy()

        return try await withCheckedThrowingContinuation { continuation in
            call(proxy) { success, errorMessage in
                if success {
                    AppLogger.shared.log("✅ [HelperManager] \(name) succeeded")
                    continuation.resume()
                } else {
                    let error = errorMessage ?? "Unknown error"
                    AppLogger.shared.log("❌ [HelperManager] \(name) failed: \(error)")
                    continuation.resume(throwing: HelperManagerError.operationFailed(error))
                }
            }
        }
    }

    // MARK: - LaunchDaemon Operations

    func installLaunchDaemon(plistPath: String, serviceID: String) async throws {
        try await executeXPCCall("installLaunchDaemon") { proxy, reply in
            proxy.installLaunchDaemon(plistPath: plistPath, serviceID: serviceID, reply: reply)
        }
    }

    func installAllLaunchDaemonServices(kanataBinaryPath: String, kanataConfigPath: String, tcpPort: Int) async throws {
        try await executeXPCCall("installAllLaunchDaemonServices") { proxy, reply in
            proxy.installAllLaunchDaemonServices(kanataBinaryPath: kanataBinaryPath, kanataConfigPath: kanataConfigPath, tcpPort: tcpPort, reply: reply)
        }
    }

    func installAllLaunchDaemonServicesWithPreferences() async throws {
        try await executeXPCCall("installAllLaunchDaemonServicesWithPreferences") { proxy, reply in
            proxy.installAllLaunchDaemonServicesWithPreferences(reply: reply)
        }
    }

    func restartUnhealthyServices() async throws {
        try await executeXPCCall("restartUnhealthyServices") { proxy, reply in
            proxy.restartUnhealthyServices(reply: reply)
        }
    }

    func regenerateServiceConfiguration() async throws {
        try await executeXPCCall("regenerateServiceConfiguration") { proxy, reply in
            proxy.regenerateServiceConfiguration(reply: reply)
        }
    }

    func installLogRotation() async throws {
        try await executeXPCCall("installLogRotation") { proxy, reply in
            proxy.installLogRotation(reply: reply)
        }
    }

    func repairVHIDDaemonServices() async throws {
        try await executeXPCCall("repairVHIDDaemonServices") { proxy, reply in
            proxy.repairVHIDDaemonServices(reply: reply)
        }
    }

    func installLaunchDaemonServicesWithoutLoading() async throws {
        try await executeXPCCall("installLaunchDaemonServicesWithoutLoading") { proxy, reply in
            proxy.installLaunchDaemonServicesWithoutLoading(reply: reply)
        }
    }

    // MARK: - VirtualHID Operations

    func activateVirtualHIDManager() async throws {
        try await executeXPCCall("activateVirtualHIDManager") { proxy, reply in
            proxy.activateVirtualHIDManager(reply: reply)
        }
    }

    func uninstallVirtualHIDDrivers() async throws {
        try await executeXPCCall("uninstallVirtualHIDDrivers") { proxy, reply in
            proxy.uninstallVirtualHIDDrivers(reply: reply)
        }
    }

    func installVirtualHIDDriver(version: String, downloadURL: String) async throws {
        try await executeXPCCall("installVirtualHIDDriver") { proxy, reply in
            proxy.installVirtualHIDDriver(version: version, downloadURL: downloadURL, reply: reply)
        }
    }

    func downloadAndInstallCorrectVHIDDriver() async throws {
        try await executeXPCCall("downloadAndInstallCorrectVHIDDriver") { proxy, reply in
            proxy.downloadAndInstallCorrectVHIDDriver(reply: reply)
        }
    }

    // MARK: - Process Management

    func terminateProcess(_ pid: Int32) async throws {
        AppLogger.shared.log("📤 [HelperManager] Calling terminateProcess(\(pid))")

        let proxy = try getRemoteProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.terminateProcess(pid) { success, errorMessage in
                if success {
                    AppLogger.shared.log("✅ [HelperManager] terminateProcess succeeded")
                    continuation.resume()
                } else {
                    let error = errorMessage ?? "Unknown error"
                    AppLogger.shared.log("❌ [HelperManager] terminateProcess failed: \(error)")
                    continuation.resume(throwing: HelperManagerError.operationFailed(error))
                }
            }
        }
    }

    func killAllKanataProcesses() async throws {
        try await executeXPCCall("killAllKanataProcesses") { proxy, reply in
            proxy.killAllKanataProcesses(reply: reply)
        }
    }

    func restartKarabinerDaemon() async throws {
        try await executeXPCCall("restartKarabinerDaemon") { proxy, reply in
            proxy.restartKarabinerDaemon(reply: reply)
        }
    }

    // Note: executeCommand removed for security. Use explicit operations only.
}

// MARK: - Error Types

/// Errors that can occur in HelperManager
enum HelperManagerError: Error, LocalizedError {
    case notInstalled
    case connectionFailed(String)
    case operationFailed(String)
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Privileged helper is not installed"
        case .connectionFailed(let reason):
            return "Failed to connect to helper: \(reason)"
        case .operationFailed(let reason):
            return "Helper operation failed: \(reason)"
        case .installationFailed(let reason):
            return "Failed to install helper: \(reason)"
        }
    }
}
