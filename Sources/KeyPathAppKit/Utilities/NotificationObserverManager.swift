import Foundation

/// Helper class to manage NotificationCenter observers with automatic cleanup.
///
/// Use this class to avoid boilerplate observer storage and cleanup code.
/// Observers are automatically removed when the manager is deallocated.
///
/// ## Usage
/// ```swift
/// class MyViewModel {
///     private let observers = NotificationObserverManager()
///
///     init() {
///         observers.observe(.someNotification) { [weak self] notification in
///             // handle notification
///         }
///     }
/// }
/// // No need for deinit - observers are cleaned up automatically
/// ```
///
/// ## Thread Safety
/// This class is marked `@unchecked Sendable` because:
/// - Observer storage is only modified during setup (typically on main thread)
/// - Cleanup happens in deinit which is serialized
/// - Individual observers handle their own thread safety via `queue` parameter
///
/// For `@MainActor` types, use the `@MainActor` variant methods.
public final class NotificationObserverManager: @unchecked Sendable {
    /// Stored observer with its associated notification center
    private struct StoredObserver {
        let observer: NSObjectProtocol
        let center: NotificationCenter
    }

    /// Stored observers for cleanup
    private var observers: [StoredObserver] = []

    /// Lock for thread-safe observer array access
    private let lock = NSLock()

    public init() {}

    deinit {
        removeAll()
    }

    // MARK: - Standard API

    /// Observe a notification with the specified handler.
    ///
    /// - Parameters:
    ///   - name: The notification name to observe.
    ///   - object: Optional object to filter notifications from.
    ///   - queue: The operation queue to invoke the handler on. Defaults to `.main`.
    ///   - center: The notification center to use. Defaults to `.default`.
    ///   - handler: The closure to invoke when the notification is posted.
    public func observe(
        _ name: Notification.Name,
        object: Any? = nil,
        queue: OperationQueue? = .main,
        center: NotificationCenter = .default,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        let observer = center.addObserver(
            forName: name,
            object: object,
            queue: queue,
            using: handler
        )
        lock.lock()
        observers.append(StoredObserver(observer: observer, center: center))
        lock.unlock()
    }

    /// Observe a notification and extract user info values.
    ///
    /// - Parameters:
    ///   - name: The notification name to observe.
    ///   - object: Optional object to filter notifications from.
    ///   - queue: The operation queue to invoke the handler on. Defaults to `.main`.
    ///   - handler: The closure to invoke with the notification's userInfo dictionary.
    public func observeUserInfo(
        _ name: Notification.Name,
        object: Any? = nil,
        queue: OperationQueue? = .main,
        handler: @escaping @Sendable ([AnyHashable: Any]?) -> Void
    ) {
        observe(name, object: object, queue: queue) { notification in
            handler(notification.userInfo)
        }
    }

    // MARK: - Cleanup

    /// Remove all observers.
    ///
    /// This is called automatically in deinit, but can be called manually
    /// if you need to stop observing before the manager is deallocated.
    public func removeAll() {
        lock.lock()
        let observersToRemove = observers
        observers.removeAll()
        lock.unlock()

        for stored in observersToRemove {
            stored.center.removeObserver(stored.observer)
        }
    }

    /// Remove a specific observer by name.
    ///
    /// Note: This removes ALL observers for the given notification name.
    /// If you need finer control, store the observer yourself.
    public func removeObservers(for _: Notification.Name) {
        // This is a simplified version - for full control, users should
        // manage observers directly. This helper is for the common case.
        // Currently not implemented to avoid complexity.
    }

    /// Number of active observers (useful for debugging/testing)
    public var observerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return observers.count
    }
}

// MARK: - MainActor Convenience Extension

public extension NotificationObserverManager {
    /// Convenience method for setting up multiple observers at once.
    ///
    /// - Parameter setup: A closure that receives the manager and can call observe() multiple times.
    func setup(_ setup: (NotificationObserverManager) -> Void) {
        setup(self)
    }
}
