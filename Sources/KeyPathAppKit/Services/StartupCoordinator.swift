import AppKit
import Foundation
import KeyPathCore

/// Coordinates a boring, phased startup to keep the first display cycle clean.
///
/// Phases (relative to first call to `start()`):
/// - T+0ms: mark painted; no side effects
/// - T+250ms: warm caches/lightweight setup (preferences, log)
/// - T+750ms: validation (permissions/install) — UI may show spinners
/// - T+1000ms: optional auto-launch attempt
/// - T+1250ms: emergency monitoring (event taps) if permitted
@MainActor
final class StartupCoordinator: ObservableObject {
    static let shared = StartupCoordinator()

    enum Phase: String { case idle, painted, warmed, validated, launched, monitoring }

    @Published private(set) var phase: Phase = .idle
    private var timers: [DispatchSourceTimer] = []

    private init() {}

    /// Begin phased startup. Safe to call multiple times; only the first run executes.
    func start() {
        guard phase == .idle else { return }

        transition(to: .painted)

        schedule(after: 0.25) { [weak self] in
            guard let self else { return }
            transition(to: .warmed)
            NotificationCenter.default.post(name: .kp_startupWarm, object: nil)
        }

        // Start auto-launch earlier so validation runs after service kick-off
        schedule(after: 0.50) { [weak self] in
            guard let self else { return }
            transition(to: .launched)
            NotificationCenter.default.post(name: .kp_startupAutoLaunch, object: nil)
        }

        schedule(after: 1.00) { [weak self] in
            guard let self else { return }
            transition(to: .validated)
            // Trigger validation via .kp_startupRevalidate notification
            NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
        }

        schedule(after: 1.25) { [weak self] in
            guard let self else { return }
            transition(to: .monitoring)
            NotificationCenter.default.post(name: .kp_startupEmergencyMonitor, object: nil)
        }
    }

    func cancel() {
        timers.forEach { $0.cancel() }
        timers.removeAll()
    }

    private func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler(handler: block)
        timer.resume()
        timers.append(timer)
    }

    private func transition(to newPhase: Phase) {
        phase = newPhase
        AppLogger.shared.log("🚦 [Startup] Phase -> \(newPhase.rawValue)")
    }
}
