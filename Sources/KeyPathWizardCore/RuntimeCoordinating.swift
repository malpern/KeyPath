import Foundation

// MARK: - Runtime Status

/// Runtime status for the Kanata service, usable across module boundaries.
/// Mirrors ServiceLifecycleCoordinator.RuntimeStatus for protocol use.
public enum WizardRuntimeStatus: Equatable, Sendable {
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

// MARK: - Repair Report

/// Simplified repair result for cross-module use.
/// RuntimeCoordinator maps InstallerReport → WizardRepairReport in its conformance.
public struct WizardRepairReport: Sendable {
    public let success: Bool
    public let successCount: Int
    public let totalCount: Int
    public let failureReason: String?

    public init(success: Bool, successCount: Int, totalCount: Int, failureReason: String?) {
        self.success = success
        self.successCount = successCount
        self.totalCount = totalCount
        self.failureReason = failureReason
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

    func currentRuntimeStatus() async -> WizardRuntimeStatus
    func isInTransientRuntimeStartupWindow() async -> Bool

    // MARK: - Settings

    func openInputMonitoringSettings()
    func openAccessibilitySettings()

    // MARK: - Queries

    func isKarabinerElementsRunning() async -> Bool
    func isKarabinerDriverInstalled() -> Bool
    func getVirtualHIDBreakageSummary() async -> String

    // MARK: - State

    var lastError: String? { get }

    // MARK: - Repair

    func runFullRepair(reason: String) async -> WizardRepairReport
}
