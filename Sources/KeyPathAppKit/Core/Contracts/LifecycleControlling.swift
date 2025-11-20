import Foundation

/// Protocol defining lifecycle management capabilities for system services.
///
/// This protocol establishes a consistent interface for starting, stopping, and monitoring
/// the state of services within KeyPath. It provides the foundation for clean separation
/// between service coordination and implementation details.
///
/// ## Usage
///
/// Services implementing this protocol should handle their lifecycle operations asynchronously
/// and maintain accurate state reporting through the `isRunning` property.
///
/// ```swift
/// class MyService: LifecycleControlling {
///     @Published private(set) var isRunning = false
///
///     func start() async throws {
///         // Service startup logic
///         isRunning = true
///     }
///
///     func stop() async throws {
///         // Service shutdown logic
///         isRunning = false
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Implementations must ensure thread-safe access to the `isRunning` property and handle
/// concurrent start/stop operations gracefully.
protocol LifecycleControlling {
  /// Indicates whether the service is currently running.
  ///
  /// This property should accurately reflect the service's operational state and be
  /// updated atomically during state transitions.
  var isRunning: Bool { get }

  /// Starts the service.
  ///
  /// This method should be idempotent - calling it multiple times when already running
  /// should not cause errors or undesired side effects.
  ///
  /// - Throws: `LifecycleError` or service-specific errors if startup fails.
  func start() async throws

  /// Stops the service gracefully.
  ///
  /// This method should handle cleanup operations and ensure the service shuts down
  /// in a clean state. Like `start()`, this should be idempotent.
  ///
  /// - Throws: `LifecycleError` or service-specific errors if shutdown fails.
  func stop() async throws
}

/// Extension providing default implementations and convenience methods.
extension LifecycleControlling {
  /// Restarts the service by stopping and then starting it.
  ///
  /// This is a convenience method that combines stop and start operations
  /// with appropriate error handling.
  ///
  /// - Throws: Errors from either the stop or start operations.
  func restart() async throws {
    try await stop()
    try await start()
  }

  /// Ensures the service is in the desired running state.
  ///
  /// - Parameter shouldBeRunning: The desired running state.
  /// - Throws: Errors from start or stop operations if state change fails.
  func ensureState(running shouldBeRunning: Bool) async throws {
    if shouldBeRunning, !isRunning {
      try await start()
    } else if !shouldBeRunning, isRunning {
      try await stop()
    }
  }
}
