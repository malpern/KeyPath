import Foundation

/// Timing constants for the runtime startup lifecycle.
///
/// These values live together so the relationship between them is explicit:
/// the UI grace period must outlast the gate polling window so the
/// "not running" error state can't flash before the gate has had a chance
/// to succeed or definitively fail.
enum RuntimeStartupTiming {
    /// How long the startup gate polls before declaring a definitive failure.
    /// Used by `MainAppStateController.evaluateKanataStartupGate`.
    /// Must cover DriverKit virtual keyboard initialization (30-90s on fresh install).
    static let gatePollingWindow: TimeInterval = 130.0

    /// How long to treat a missing runtime as "starting" in user-facing UI.
    /// Must be >= `gatePollingWindow` so the wizard and overlay never show
    /// a failure state before the gate itself has had time to resolve.
    static let uiGracePeriod: TimeInterval = 140.0
}

/// Pure, testable evaluator that decides whether we are inside the
/// "runtime is probably starting up, don't alarm the user" window.
///
/// No clocks or singletons — all inputs are passed in. Makes the logic
/// trivial to unit-test.
struct TransientStartupWindowEvaluator {
    let gracePeriod: TimeInterval
    let createdAt: Date

    func isInWindow(
        now: Date,
        isStarting: Bool,
        lastStartAttemptAt: Date?,
        isSMAppServicePending: Bool
    ) -> Bool {
        if isStarting {
            return true
        }
        if now.timeIntervalSince(createdAt) < gracePeriod {
            return true
        }
        if let lastStartAttemptAt,
           now.timeIntervalSince(lastStartAttemptAt) < gracePeriod
        {
            return true
        }
        return isSMAppServicePending
    }
}
