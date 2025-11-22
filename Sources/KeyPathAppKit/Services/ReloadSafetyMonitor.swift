import Foundation
import KeyPathCore

/// Tracks reload operations and detects patterns that indicate daemon crashes
///
/// This monitor implements three safety mechanisms:
/// 1. **TCP Reload Error Detection**: Tracks when reload commands correlate with daemon crashes
/// 2. **Reload Cooldown**: Prevents reload spam that could trigger crash loops
/// 3. **Crash Loop Detection**: Identifies rapid restart patterns and backs off
///
/// Design:
/// - Uses sliding window to track recent reload attempts
/// - Correlates reload timing with service restarts
/// - Implements exponential backoff when crashes detected
/// - Thread-safe via actor isolation
actor ReloadSafetyMonitor {
    // MARK: - Configuration

    /// Minimum time between reload attempts (prevents spam)
    private let reloadCooldownSeconds: TimeInterval = 2.0

    /// Time window to track reload history
    private let trackingWindowSeconds: TimeInterval = 60.0

    /// Number of restarts in window that indicates a crash loop
    private let crashLoopThreshold = 3

    /// Time to wait after detecting crash loop before allowing reloads
    private let crashLoopBackoffSeconds: TimeInterval = 30.0

    // MARK: - State

    /// History of reload attempts with timestamps
    private struct ReloadAttempt {
        let timestamp: Date
        let succeeded: Bool
        let daemonPID: Int?
    }

    private var reloadHistory: [ReloadAttempt] = []

    /// Last time a reload was attempted
    private var lastReloadTime: Date?

    /// Detected crash loop state
    private var crashLoopDetectedAt: Date?

    /// Service restart history (PID changes indicate restarts)
    private var restartHistory: [(timestamp: Date, pid: Int)] = []

    // MARK: - Public API

    /// Check if it's safe to perform a reload right now
    /// - Parameters:
    ///   - currentPID: The current daemon PID (if known)
    /// - Returns: SafetyCheck result with reasoning
    func checkReloadSafety(currentPID _: Int?) -> SafetyCheck {
        let now = Date()

        // Check 1: Crash loop backoff
        if let crashTime = crashLoopDetectedAt {
            let timeSinceCrash = now.timeIntervalSince(crashTime)
            if timeSinceCrash < crashLoopBackoffSeconds {
                let remaining = crashLoopBackoffSeconds - timeSinceCrash
                AppLogger.shared.warn(
                    "⛔️ [ReloadSafety] In crash loop backoff - \(Int(remaining))s remaining")
                return .unsafe(reason: "Crash loop detected - backing off for \(Int(remaining))s")
            } else {
                // Backoff expired - clear crash loop state
                AppLogger.shared.log(
                    "✅ [ReloadSafety] Crash loop backoff expired - resuming normal operation")
                crashLoopDetectedAt = nil
            }
        }

        // Check 2: Reload cooldown
        if let lastReload = lastReloadTime {
            let timeSinceLastReload = now.timeIntervalSince(lastReload)
            if timeSinceLastReload < reloadCooldownSeconds {
                let remaining = reloadCooldownSeconds - timeSinceLastReload
                AppLogger.shared.debug(
                    "⏱️ [ReloadSafety] Reload cooldown active - \(String(format: "%.1f", remaining))s remaining"
                )
                return .unsafe(reason: "Reload cooldown - \(String(format: "%.1f", remaining))s remaining")
            }
        }

        // Check 3: Recent restart rate
        let recentRestarts = countRecentRestarts(within: trackingWindowSeconds)
        if recentRestarts >= crashLoopThreshold {
            AppLogger.shared.error(
                "🚨 [ReloadSafety] Crash loop detected - \(recentRestarts) restarts in last \(Int(trackingWindowSeconds))s"
            )
            crashLoopDetectedAt = now
            return .unsafe(
                reason: "Crash loop detected - \(recentRestarts) restarts in \(Int(trackingWindowSeconds))s"
            )
        }

        AppLogger.shared.debug("✅ [ReloadSafety] Safety checks passed")
        return .safe
    }

    /// Record a reload attempt
    /// - Parameters:
    ///   - succeeded: Whether the reload succeeded
    ///   - daemonPID: The daemon PID at time of reload (if known)
    func recordReloadAttempt(succeeded: Bool, daemonPID: Int?) {
        let now = Date()
        let attempt = ReloadAttempt(timestamp: now, succeeded: succeeded, daemonPID: daemonPID)
        reloadHistory.append(attempt)
        lastReloadTime = now

        // Cleanup old history
        cleanupOldHistory()

        if !succeeded {
            AppLogger.shared.warn("⚠️ [ReloadSafety] Reload failed - monitoring for potential crash")
        }
    }

    /// Record a service restart (PID change)
    /// - Parameter pid: The new daemon PID
    func recordServiceRestart(pid: Int) {
        let now = Date()
        restartHistory.append((timestamp: now, pid: pid))

        // Cleanup old history
        cleanupOldHistory()

        // Check if this restart happened shortly after a reload (potential crash)
        if let lastReload = lastReloadTime {
            let timeSinceReload = now.timeIntervalSince(lastReload)
            if timeSinceReload < 60.0 { // Within 60 seconds
                AppLogger.shared.warn(
                    "⚠️ [ReloadSafety] Service restarted \(Int(timeSinceReload))s after reload - potential crash"
                )

                // Check if this is part of a crash loop pattern
                let recentRestarts = countRecentRestarts(within: trackingWindowSeconds)
                if recentRestarts >= crashLoopThreshold {
                    AppLogger.shared.error(
                        "🚨 [ReloadSafety] Crash loop detected! \(recentRestarts) restarts in \(Int(trackingWindowSeconds))s"
                    )
                    crashLoopDetectedAt = now
                }
            }
        }
    }

    /// Get current safety status for debugging
    func getStatus() -> SafetyStatus {
        let now = Date()
        let recentRestarts = countRecentRestarts(within: trackingWindowSeconds)
        let recentReloads = reloadHistory.filter {
            now.timeIntervalSince($0.timestamp) < trackingWindowSeconds
        }.count

        let cooldownRemaining: TimeInterval?
        if let lastReload = lastReloadTime {
            let elapsed = now.timeIntervalSince(lastReload)
            cooldownRemaining = elapsed < reloadCooldownSeconds ? (reloadCooldownSeconds - elapsed) : nil
        } else {
            cooldownRemaining = nil
        }

        let backoffRemaining: TimeInterval?
        if let crashTime = crashLoopDetectedAt {
            let elapsed = now.timeIntervalSince(crashTime)
            backoffRemaining =
                elapsed < crashLoopBackoffSeconds ? (crashLoopBackoffSeconds - elapsed) : nil
        } else {
            backoffRemaining = nil
        }

        return SafetyStatus(
            inCrashLoop: crashLoopDetectedAt != nil,
            recentRestarts: recentRestarts,
            recentReloads: recentReloads,
            cooldownRemaining: cooldownRemaining,
            backoffRemaining: backoffRemaining
        )
    }

    // MARK: - Private Helpers

    private func countRecentRestarts(within seconds: TimeInterval) -> Int {
        let cutoff = Date().addingTimeInterval(-seconds)
        return restartHistory.filter { $0.timestamp > cutoff }.count
    }

    private func cleanupOldHistory() {
        let cutoff = Date().addingTimeInterval(-trackingWindowSeconds)
        reloadHistory.removeAll { $0.timestamp < cutoff }
        restartHistory.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Types

    enum SafetyCheck {
        case safe
        case unsafe(reason: String)

        var isSafe: Bool {
            if case .safe = self { return true }
            return false
        }

        var reason: String? {
            if case let .unsafe(reason) = self { return reason }
            return nil
        }
    }

    struct SafetyStatus {
        let inCrashLoop: Bool
        let recentRestarts: Int
        let recentReloads: Int
        let cooldownRemaining: TimeInterval?
        let backoffRemaining: TimeInterval?

        var description: String {
            var parts: [String] = []
            if inCrashLoop {
                parts.append("CRASH LOOP")
            }
            parts.append("\(recentRestarts) restarts")
            parts.append("\(recentReloads) reloads")
            if let cooldown = cooldownRemaining {
                parts.append("cooldown: \(String(format: "%.1f", cooldown))s")
            }
            if let backoff = backoffRemaining {
                parts.append("backoff: \(Int(backoff))s")
            }
            return parts.joined(separator: ", ")
        }
    }
}
