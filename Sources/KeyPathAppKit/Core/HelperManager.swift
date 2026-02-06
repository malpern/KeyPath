import Foundation
import KeyPathCore
import ServiceManagement

/// Manager for XPC communication with the privileged helper
///
/// This actor owns helper connection state and shared constants. Operation-specific
/// behavior is split into focused extensions for maintainability.
actor HelperManager {
    // MARK: - Helper Health State

    enum HealthState: Equatable {
        case notInstalled
        case requiresApproval(String?)
        case registeredButUnresponsive(String?)
        case healthy(version: String?)
    }

    // MARK: - SMAppService indirection for testability

    // Allows unit tests to inject a fake SMAppService and simulate states like `.notFound`.
    // Default implementation wraps Apple's `SMAppService`.
    nonisolated(unsafe) static var smServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
        NativeSMAppService(wrapped: ServiceManagement.SMAppService.daemon(plistName: plistName))
    }

    nonisolated(unsafe) static var testHelperFunctionalityOverride: (() async -> Bool)?
    nonisolated(unsafe) static var testInstallHelperOverride: (() async throws -> Void)?
    nonisolated(unsafe) static var subprocessRunnerFactory: () -> SubprocessRunning = {
        SubprocessRunner.shared
    }

    // MARK: - Singleton

    static let shared = HelperManager()

    // MARK: - Properties

    /// XPC connection to the privileged helper
    // Internal so lifecycle/IPC extensions in separate files can manage connection state.
    var connection: NSXPCConnection?

    /// Mach service name for the helper (type-level constant)
    static let helperMachServiceName = "com.keypath.helper"

    /// Bundle identifier / label for the helper (type-level constant)
    static let helperBundleIdentifier = "com.keypath.helper"

    /// LaunchDaemon plist name packaged inside the app bundle for SMAppService
    static let helperPlistName = "com.keypath.helper.plist"

    /// Expected helper version (should match HelperService.version)
    static let expectedHelperVersion = "1.0.0"

    /// Cached helper version (lazy loaded)
    var cachedHelperVersion: String?

    /// Active XPC call tracking for detecting concurrency issues
    var activeXPCCalls: Set<String> = []

    // MARK: - Initialization

    private init() {
        AppLogger.shared.log("🔧 [HelperManager] Initialized")
    }

    deinit {
        // Note: Cannot safely access MainActor-isolated connection from deinit
        // Connection will be invalidated when the XPC connection is deallocated
    }
}

// MARK: - SMAppService test seam

protocol SMAppServiceProtocol: Sendable {
    var status: ServiceManagement.SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

struct NativeSMAppService: SMAppServiceProtocol, @unchecked Sendable {
    private let wrapped: ServiceManagement.SMAppService
    init(wrapped: ServiceManagement.SMAppService) { self.wrapped = wrapped }
    var status: ServiceManagement.SMAppService.Status { wrapped.status }
    func register() throws { try wrapped.register() }
    func unregister() async throws { if #available(macOS 13, *) { try await wrapped.unregister() } }
}

// MARK: - Error Types

/// Errors that can occur in HelperManager
enum HelperManagerError: Error, LocalizedError {
    case notInstalled
    case connectionFailed(String)
    case operationFailed(String)
    case installationFailed(String)
    case signatureMismatch

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Privileged helper is not installed"
        case let .connectionFailed(reason):
            "Failed to connect to helper: \(reason)"
        case let .operationFailed(reason):
            "Helper operation failed: \(reason)"
        case let .installationFailed(reason):
            "Failed to install helper: \(reason)"
        case .signatureMismatch:
            "App signature mismatch - restart required"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .signatureMismatch:
            "KeyPath was recently updated. Please restart the app to load the new version."
        case .connectionFailed:
            "Try restarting KeyPath. If the problem persists, reinstall the app."
        case .notInstalled:
            "Run the installation wizard to set up KeyPath."
        case .operationFailed, .installationFailed:
            "Check the logs for more details. You may need to restart KeyPath."
        }
    }
}
