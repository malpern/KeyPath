import Foundation

// MARK: - Runtime Status

/// The session runtime's state, as ServiceLifecycleCoordinator reports it.
/// Lives here so the app and the wizard module share one definition.
public enum RuntimeStatus: Equatable, Sendable {
    case running(pid: Int)
    case stopped
    case failed(reason: String)
    case starting
    case unknown

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

// MARK: - RuntimeCoordinating Protocol

/// Protocol abstracting RuntimeCoordinator for use by the wizard module.
/// The wizard module cannot import KeyPathAppKit directly (it would be circular),
/// so it accesses RuntimeCoordinator through this protocol.
@MainActor
public protocol RuntimeCoordinating: AnyObject, Sendable {
    // MARK: - Service Lifecycle

    @discardableResult
    func startKanata(reason: String) async -> Bool

    @discardableResult
    func stopKanata(reason: String) async -> Bool

    @discardableResult
    func restartKanata(reason: String) async -> Bool

    func updateStatus() async

    func currentRuntimeStatus() async -> RuntimeStatus
    func isInTransientRuntimeStartupWindow() async -> Bool

    // MARK: - Settings

    func openAccessibilitySettings()

    // MARK: - State

    var lastError: String? { get }
}
