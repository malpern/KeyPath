import Foundation

// MARK: - Service Management State

/// Represents the current state of service management for Kanata daemon.
/// Mirrors KanataDaemonManager.ServiceManagementState for cross-module use.
public enum WizardServiceManagementState: Equatable, Sendable {
    case legacyActive
    case smappserviceActive
    case smappservicePending
    case uninstalled
    case conflicted
    case unknown

    public var description: String {
        switch self {
        case .legacyActive: "Legacy launchctl"
        case .smappserviceActive: "SMAppService (active)"
        case .smappservicePending: "SMAppService (pending approval)"
        case .uninstalled: "Uninstalled"
        case .conflicted: "Conflicted (legacy + SMAppService)"
        case .unknown: "Unknown"
        }
    }

    /// Returns true if SMAppService is the active management method
    public var isSMAppServiceManaged: Bool {
        self == .smappserviceActive || self == .smappservicePending
    }
}

// MARK: - WizardDaemonManaging Protocol

/// Protocol abstracting KanataDaemonManager for use by the wizard module.
/// Covers only the methods that wizard files actually call.
@MainActor
public protocol WizardDaemonManaging: AnyObject, Sendable {
    @discardableResult
    func refreshManagementState() async -> WizardServiceManagementState

    func isRegisteredButNotLoaded() async -> Bool

    func register() async throws
    func unregister() async throws

    nonisolated var kanataServiceID: String { get }
    nonisolated var legacyPlistPath: String { get }

    func preferredLaunchctlTargets(for state: WizardServiceManagementState) -> [String]
}
