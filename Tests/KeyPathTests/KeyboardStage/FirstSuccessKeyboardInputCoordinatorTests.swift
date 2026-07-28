@testable import KeyPathAppKit
import XCTest

@MainActor
final class FirstSuccessKeyboardInputCoordinatorTests: XCTestCase {
    func testPressRepeatAndReleaseTrackOnlyCurrentKeys() {
        let coordinator = FirstSuccessKeyboardInputCoordinator()

        coordinator.receiveKeyInput(key: "caps", action: "press", listenerSessionID: 4)
        let pressRevision = coordinator.interaction.revision
        XCTAssertEqual(coordinator.interaction.pressedKeyCodes, [57])
        XCTAssertEqual(coordinator.interaction.phase, .press)

        coordinator.receiveKeyInput(key: "caps", action: "repeat", listenerSessionID: 4)
        XCTAssertEqual(coordinator.interaction.revision, pressRevision)

        coordinator.receiveKeyInput(key: "caps", action: "release", listenerSessionID: 4)
        XCTAssertTrue(coordinator.interaction.pressedKeyCodes.isEmpty)
        XCTAssertEqual(coordinator.interaction.phase, .release)
        XCTAssertGreaterThan(coordinator.interaction.revision, pressRevision)
    }

    func testHoldActivationAddsSemanticHoldUntilRelease() {
        let coordinator = FirstSuccessKeyboardInputCoordinator()

        coordinator.receiveHoldActivated(key: "caps", listenerSessionID: 2)

        XCTAssertEqual(coordinator.interaction.pressedKeyCodes, [57])
        XCTAssertEqual(coordinator.interaction.heldKeyCodes, [57])
        XCTAssertEqual(coordinator.interaction.phase, .hold)

        coordinator.receiveKeyInput(key: "caps", action: "release", listenerSessionID: 2)

        XCTAssertTrue(coordinator.interaction.pressedKeyCodes.isEmpty)
        XCTAssertTrue(coordinator.interaction.heldKeyCodes.isEmpty)
    }

    func testNewListenerSessionClearsStalePressedKeys() {
        let coordinator = FirstSuccessKeyboardInputCoordinator()
        coordinator.receiveKeyInput(key: "a", action: "press", listenerSessionID: 8)

        coordinator.receiveKeyInput(key: "s", action: "press", listenerSessionID: 9)

        XCTAssertEqual(coordinator.interaction.pressedKeyCodes, [1])
    }

    func testOnlyCapsTapAdvancesPracticeEvidence() {
        let coordinator = FirstSuccessKeyboardInputCoordinator()

        coordinator.receiveTapActivated(key: "a", listenerSessionID: 1)
        XCTAssertEqual(coordinator.capsTapRevision, 0)

        coordinator.receiveTapActivated(key: "capslock", listenerSessionID: 1)
        XCTAssertEqual(coordinator.capsTapRevision, 1)
    }

    func testNotificationBridgeStopsAndClearsState() async {
        let center = NotificationCenter()
        let coordinator = FirstSuccessKeyboardInputCoordinator(notificationCenter: center)
        coordinator.start()

        center.post(
            name: .kanataKeyInput,
            object: nil,
            userInfo: [
                "key": "q",
                "action": "press",
                "listenerSessionID": 7,
            ]
        )
        await yieldUntil { coordinator.interaction.pressedKeyCodes == [12] }
        XCTAssertEqual(coordinator.interaction.pressedKeyCodes, [12])

        coordinator.stop()
        let stoppedRevision = coordinator.interaction.revision
        XCTAssertTrue(coordinator.interaction.pressedKeyCodes.isEmpty)

        center.post(
            name: .kanataKeyInput,
            object: nil,
            userInfo: ["key": "w", "action": "press"]
        )
        await Task.yield()
        XCTAssertEqual(coordinator.interaction.revision, stoppedRevision)
        XCTAssertTrue(coordinator.interaction.pressedKeyCodes.isEmpty)
    }

    func testNotificationBridgePreservesPressReleaseOrder() {
        let center = NotificationCenter()
        let coordinator = FirstSuccessKeyboardInputCoordinator(notificationCenter: center)
        coordinator.start()

        center.post(
            name: .kanataKeyInput,
            object: nil,
            userInfo: ["key": "q", "action": "press"]
        )
        center.post(
            name: .kanataKeyInput,
            object: nil,
            userInfo: ["key": "q", "action": "release"]
        )

        XCTAssertEqual(coordinator.interaction.revision, 2)
        XCTAssertTrue(coordinator.interaction.pressedKeyCodes.isEmpty)
        XCTAssertEqual(coordinator.interaction.phase, .release)
        coordinator.stop()
    }

    func testMissingHeartbeatClearsStrandedPressedStateAfterTimeout() async {
        let center = NotificationCenter()
        let coordinator = FirstSuccessKeyboardInputCoordinator(
            notificationCenter: center,
            staleStateTimeout: .nanoseconds(1),
            staleStateSleep: { _ in }
        )
        coordinator.start()

        center.post(
            name: .kanataKeyInput,
            object: nil,
            userInfo: ["key": "q", "action": "press"]
        )
        await yieldUntil { coordinator.interaction.revision == 2 }

        XCTAssertTrue(coordinator.interaction.pressedKeyCodes.isEmpty)
        XCTAssertEqual(coordinator.interaction.phase, .release)
        coordinator.stop()
    }

    func testConfigReloadClearsStrandedPressedStateImmediately() {
        let center = NotificationCenter()
        let coordinator = FirstSuccessKeyboardInputCoordinator(notificationCenter: center)
        coordinator.start()

        center.post(
            name: .kanataKeyInput,
            object: nil,
            userInfo: ["key": "q", "action": "press"]
        )
        XCTAssertEqual(coordinator.interaction.pressedKeyCodes, [12])

        center.post(name: .kanataConfigChanged, object: nil)

        XCTAssertTrue(coordinator.interaction.pressedKeyCodes.isEmpty)
        XCTAssertEqual(coordinator.interaction.phase, .release)
        coordinator.stop()
    }

    func testAnonymousHeartbeatDoesNotExtendSessionScopedRecoveryDeadline() async {
        let center = NotificationCenter()
        let sleeper = SuspendedSleeper()
        let coordinator = FirstSuccessKeyboardInputCoordinator(
            notificationCenter: center,
            staleStateSleep: { _ in await sleeper.sleep() }
        )
        coordinator.start()

        center.post(
            name: .kanataKeyInput,
            object: nil,
            userInfo: [
                "key": "q",
                "action": "press",
                "listenerSessionID": 7,
            ]
        )
        await yieldUntilAsync { await sleeper.waiterCount == 1 }

        center.post(name: .kanataTcpHeartbeat, object: nil)
        for _ in 0 ..< 5 {
            await Task.yield()
        }

        let waiterCount = await sleeper.waiterCount
        XCTAssertEqual(waiterCount, 1)

        await sleeper.resumeAll()
        await yieldUntil { coordinator.interaction.pressedKeyCodes.isEmpty }
        XCTAssertTrue(coordinator.interaction.pressedKeyCodes.isEmpty)
        coordinator.stop()
    }

    private func yieldUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 20 {
            if condition() { return }
            await Task.yield()
        }
    }

    private func yieldUntilAsync(
        _ condition: () async -> Bool
    ) async {
        for _ in 0 ..< 20 {
            if await condition() { return }
            await Task.yield()
        }
    }
}

private actor SuspendedSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var waiterCount: Int {
        continuations.count
    }

    func sleep() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
