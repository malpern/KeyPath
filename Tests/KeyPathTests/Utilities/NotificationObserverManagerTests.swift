import Foundation
@testable import KeyPathAppKit
import Testing

/// Thread-safe box for capturing values in @Sendable closures.
private final class SendableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}

private final class SendableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool = false
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set() {
        lock.lock()
        _value = true
        lock.unlock()
    }
}

private final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T?
    var value: T? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ newValue: T) {
        lock.lock()
        _value = newValue
        lock.unlock()
    }
}

@Suite("NotificationObserverManager Tests")
struct NotificationObserverManagerTests {

    // MARK: - Observer Count

    @Test("initial observerCount is zero")
    func initialObserverCountIsZero() {
        let manager = NotificationObserverManager()
        #expect(manager.observerCount == 0)
    }

    @Test("observe increments observerCount")
    func observeIncrementsObserverCount() {
        let manager = NotificationObserverManager()
        let name = Notification.Name("test-\(UUID())")
        manager.observe(name, queue: nil) { _ in }
        #expect(manager.observerCount == 1)
    }

    @Test("multiple observers tracked")
    func multipleObserversTracked() {
        let manager = NotificationObserverManager()
        for i in 0 ..< 3 {
            let name = Notification.Name("test-multi-\(i)-\(UUID())")
            manager.observe(name, queue: nil) { _ in }
        }
        #expect(manager.observerCount == 3)
    }

    @Test("removeAll resets count to zero")
    func removeAllResetsCountToZero() {
        let manager = NotificationObserverManager()
        for i in 0 ..< 3 {
            let name = Notification.Name("test-remove-\(i)-\(UUID())")
            manager.observe(name, queue: nil) { _ in }
        }
        #expect(manager.observerCount == 3)
        manager.removeAll()
        #expect(manager.observerCount == 0)
    }

    // MARK: - Handler Delivery

    @Test("observer receives posted notification")
    func observerReceivesPostedNotification() {
        let manager = NotificationObserverManager()
        let name = Notification.Name("test-\(UUID())")
        let received = SendableFlag()
        manager.observe(name, queue: nil) { _ in
            received.set()
        }
        NotificationCenter.default.post(name: name, object: nil)
        #expect(received.value)
    }

    @Test("observeUserInfo receives userInfo")
    func observeUserInfoReceivesUserInfo() {
        let manager = NotificationObserverManager()
        let name = Notification.Name("test-userinfo-\(UUID())")
        let receivedKey = SendableBox<String>()
        let receivedNumber = SendableBox<Int>()
        manager.observeUserInfo(name, queue: nil) { info in
            receivedKey.set(info?["key"] as? String ?? "")
            receivedNumber.set(info?["number"] as? Int ?? -1)
        }
        let userInfo: [AnyHashable: Any] = ["key": "value", "number": 42]
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        #expect(receivedKey.value == "value")
        #expect(receivedNumber.value == 42)
    }

    @Test("observer does not fire after removeAll")
    func observerDoesNotFireAfterRemoveAll() {
        let manager = NotificationObserverManager()
        let name = Notification.Name("test-nofire-\(UUID())")
        let callCount = SendableCounter()
        manager.observe(name, queue: nil) { _ in
            callCount.increment()
        }
        // Fire once before removeAll to confirm it works
        NotificationCenter.default.post(name: name, object: nil)
        #expect(callCount.value == 1)
        manager.removeAll()
        // Fire again after removeAll -- should not increment
        NotificationCenter.default.post(name: name, object: nil)
        #expect(callCount.value == 1)
    }

    // MARK: - Setup Convenience

    @Test("setup convenience calls closure with self")
    func setupConvenienceCallsClosureWithSelf() {
        let manager = NotificationObserverManager()
        var receivedManager: NotificationObserverManager?
        manager.setup { mgr in
            receivedManager = mgr
        }
        #expect(receivedManager === manager)
    }

    // MARK: - Deinit Cleanup

    @Test("deinit removes observers")
    func deinitRemovesObservers() {
        let name = Notification.Name("test-deinit-\(UUID())")
        let callCount = SendableCounter()

        // Create manager in a limited scope so it deallocates
        do {
            let manager = NotificationObserverManager()
            manager.observe(name, queue: nil) { _ in
                callCount.increment()
            }
            // Verify it works while alive
            NotificationCenter.default.post(name: name, object: nil)
            #expect(callCount.value == 1)
        }
        // Manager has been deallocated -- observer should be removed
        NotificationCenter.default.post(name: name, object: nil)
        #expect(callCount.value == 1, "Handler should not fire after manager is deallocated")
    }

    // MARK: - Independence

    @Test("observers from different notification names are independent")
    func observersFromDifferentNamesAreIndependent() {
        let manager = NotificationObserverManager()
        let nameA = Notification.Name("test-A-\(UUID())")
        let nameB = Notification.Name("test-B-\(UUID())")
        let receivedA = SendableFlag()
        let receivedB = SendableFlag()
        manager.observe(nameA, queue: nil) { _ in
            receivedA.set()
        }
        manager.observe(nameB, queue: nil) { _ in
            receivedB.set()
        }
        // Post only nameA
        NotificationCenter.default.post(name: nameA, object: nil)
        #expect(receivedA.value)
        #expect(!receivedB.value, "Handler for nameB should not fire when only nameA is posted")
    }
}
