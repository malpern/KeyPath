import Foundation
import KeyPathCore

/// Publishes UI state changes via AsyncStream for reactive ViewModel updates.
///
/// This service provides:
/// - AsyncStream for UI state changes (replaces polling)
/// - State snapshot creation for ViewModel synchronization
/// - Efficient change notification (only emits when state changes)
///
/// ## Usage
///
/// ```swift
/// let publisher = StatePublisherService<KanataUIState>()
/// publisher.configure { self.buildUIState() }
///
/// // In ViewModel:
/// for await state in publisher.stateChanges {
///     self.updateUI(with: state)
/// }
///
/// // When state changes:
/// publisher.notifyStateChanged()
/// ```
@MainActor
final class StatePublisherService<State: Sendable> {
    // MARK: - Properties

    /// AsyncStream continuation for emitting state changes
    private var stateChangeContinuation: AsyncStream<State>.Continuation?

    /// Provider function that creates state snapshots
    private var stateProvider: (() -> State)?

    // MARK: - Public Interface

    /// Stream of state changes for reactive updates.
    ///
    /// Subscribers receive:
    /// - Initial state immediately upon subscription
    /// - Subsequent states when `notifyStateChanged()` is called
    ///
    /// - Note: This property is nonisolated to allow subscription from any context.
    nonisolated var stateChanges: AsyncStream<State> {
        AsyncStream { continuation in
            Task { @MainActor in
                self.stateChangeContinuation = continuation
                // Emit initial state if provider is configured
                if let provider = self.stateProvider {
                    continuation.yield(provider())
                }
            }
        }
    }

    /// Configure the state provider function.
    ///
    /// - Parameter provider: A function that returns the current state snapshot.
    ///   This is called each time state needs to be published.
    func configure(stateProvider: @escaping () -> State) {
        self.stateProvider = stateProvider
    }

    /// Notify observers that state has changed.
    ///
    /// Call this after any operation that modifies UI-visible state.
    /// The configured state provider will be invoked to create a new snapshot.
    func notifyStateChanged() {
        guard let provider = stateProvider else {
            AppLogger.shared.warn("⚠️ [StatePublisher] notifyStateChanged called but no provider configured")
            return
        }
        let state = provider()
        stateChangeContinuation?.yield(state)
    }

    /// Get the current state snapshot without notifying observers.
    ///
    /// - Returns: Current state, or nil if provider is not configured.
    func getCurrentState() -> State? {
        stateProvider?()
    }

    /// Check if the publisher is configured and ready.
    var isConfigured: Bool {
        stateProvider != nil
    }

    /// Check if there are active subscribers.
    var hasSubscribers: Bool {
        stateChangeContinuation != nil
    }
}
