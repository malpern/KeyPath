import AppKit
import Foundation
import KeyPathCore

/// Tiny service to run a post-start safety timeout that can trigger a stop callback.
/// UI presentation (alerts) must be provided by the caller via the `onTimeout` closure.
final class SafetyTimeoutService {
  /// Start a safety timeout. After `durationSeconds`, `shouldStop()` is checked and if true, `onTimeout()` is invoked.
  /// - Parameters:
  ///   - durationSeconds: Timeout length in seconds (default 30s)
  ///   - shouldStop: Async closure returning whether the service is still running and should be stopped
  ///   - onTimeout: Async closure invoked to perform the stop and any UI notification
  func start(
    durationSeconds: TimeInterval = 30.0,
    shouldStop: @Sendable @escaping () async -> Bool,
    onTimeout: @Sendable @escaping () async -> Void
  ) {
    Task {
      // Wait for the timeout
      let ns = UInt64(durationSeconds * 1_000_000_000)
      try? await Task.sleep(nanoseconds: ns)

      // Check condition and execute
      if await shouldStop() {
        AppLogger.shared.log("⚠️ [Safety] Timeout reached - executing onTimeout()")
        await onTimeout()
      }
    }
  }
}
