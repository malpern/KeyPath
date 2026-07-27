import Foundation
import KeyPathCore
import Observation

/// A window-scoped bridge from KeyPath's existing privacy-safe Kanata events
/// to transient keyboard-stage feedback. It stores only keys that are down now;
/// it never keeps typed text or a key history.
@MainActor
@Observable
final class FirstSuccessKeyboardInputCoordinator {
    private(set) var interaction = KeyboardStageInteractionState.idle
    private(set) var capsTapRevision: UInt64 = 0

    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let staleStateTimeout: Duration
    @ObservationIgnored private let staleStateSleep: @Sendable (Duration) async -> Void
    @ObservationIgnored private let observers = NotificationObserverManager()
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var listenerSessionID: Int?
    @ObservationIgnored private var staleStateTask: Task<Void, Never>?

    init(
        notificationCenter: NotificationCenter = .default,
        staleStateTimeout: Duration = .seconds(KeyPathConstants.Timing.tcpConnectionTimeout),
        staleStateSleep: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.notificationCenter = notificationCenter
        self.staleStateTimeout = staleStateTimeout
        self.staleStateSleep = staleStateSleep
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true

        observers.observe(
            .kanataKeyInput,
            queue: .main,
            center: notificationCenter
        ) { [weak self] notification in
            let key = notification.userInfo?["key"] as? String
            let action = notification.userInfo?["action"] as? String
            let sessionID = notification.userInfo?["listenerSessionID"] as? Int
            MainActor.assumeIsolated {
                guard let self, self.isObserving,
                      let key,
                      let action
                else {
                    return
                }
                self.receiveKeyInput(
                    key: key,
                    action: action,
                    listenerSessionID: sessionID
                )
            }
        }

        observers.observe(
            .kanataHoldActivated,
            queue: .main,
            center: notificationCenter
        ) { [weak self] notification in
            let key = notification.userInfo?["key"] as? String
            let sessionID = notification.userInfo?["listenerSessionID"] as? Int
            MainActor.assumeIsolated {
                guard let self, self.isObserving,
                      let key
                else {
                    return
                }
                self.receiveHoldActivated(
                    key: key,
                    listenerSessionID: sessionID
                )
            }
        }

        observers.observe(
            .kanataTapActivated,
            queue: .main,
            center: notificationCenter
        ) { [weak self] notification in
            let key = notification.userInfo?["key"] as? String
            let sessionID = notification.userInfo?["listenerSessionID"] as? Int
            MainActor.assumeIsolated {
                guard let self, self.isObserving,
                      let key
                else {
                    return
                }
                self.receiveTapActivated(
                    key: key,
                    listenerSessionID: sessionID
                )
            }
        }

        observers.observe(
            .kanataTcpHeartbeat,
            queue: .main,
            center: notificationCenter
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isObserving else { return }
                // A layer-poll heartbeat has no listener session identity. Once
                // a physical key event establishes a session, letting anonymous
                // heartbeats extend its deadline could preserve a stranded key
                // forever across a listener reconnect. Repeats and other
                // session-scoped key events still refresh the deadline.
                guard self.listenerSessionID == nil else { return }
                self.noteTCPActivity()
            }
        }

        observers.observe(
            .kanataConfigChanged,
            queue: .main,
            center: notificationCenter
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isObserving else { return }
                self.listenerSessionID = nil
                self.clearInteraction()
            }
        }
    }

    func stop() {
        isObserving = false
        observers.removeAll()
        listenerSessionID = nil
        clearInteraction()
    }

    func receiveKeyInput(
        key: String,
        action: String,
        listenerSessionID: Int? = nil
    ) {
        defer { noteTCPActivity() }
        guard let keyCode = KanataKeyCodeMap.keyCode(for: key) else { return }
        prepareSession(listenerSessionID)
        var next = interaction

        switch action.lowercased() {
        case "press":
            guard next.pressedKeyCodes.insert(keyCode).inserted else { return }
            next.phase = .press

        case "repeat":
            return

        case "release":
            let removedPress = next.pressedKeyCodes.remove(keyCode) != nil
            let removedHold = next.heldKeyCodes.remove(keyCode) != nil
            guard removedPress || removedHold else { return }
            next.phase = .release

        default:
            return
        }

        publish(next)
    }

    func receiveHoldActivated(key: String, listenerSessionID: Int? = nil) {
        defer { noteTCPActivity() }
        guard let keyCode = KanataKeyCodeMap.keyCode(for: key) else { return }
        prepareSession(listenerSessionID)
        var next = interaction
        let insertedPress = next.pressedKeyCodes.insert(keyCode).inserted
        let insertedHold = next.heldKeyCodes.insert(keyCode).inserted
        guard insertedPress || insertedHold else { return }
        next.phase = .hold
        publish(next)
    }

    func receiveTapActivated(key: String, listenerSessionID: Int? = nil) {
        defer { noteTCPActivity() }
        guard let keyCode = KanataKeyCodeMap.keyCode(for: key) else { return }
        prepareSession(listenerSessionID)

        guard keyCode == 57 else { return }
        capsTapRevision &+= 1
    }

    private func prepareSession(_ sessionID: Int?) {
        guard let sessionID else { return }

        if let listenerSessionID, listenerSessionID != sessionID {
            clearInteraction()
        }
        listenerSessionID = sessionID
    }

    private func publish(_ next: KeyboardStageInteractionState) {
        var next = next
        next.revision &+= 1
        interaction = next
    }

    private func noteTCPActivity() {
        cancelStaleStateTimeout()
        guard isObserving,
              !interaction.pressedKeyCodes.isEmpty || !interaction.heldKeyCodes.isEmpty
        else {
            return
        }

        let expectedRevision = interaction.revision
        let timeout = staleStateTimeout
        let sleep = staleStateSleep
        staleStateTask = Task { @MainActor [weak self] in
            await sleep(timeout)
            guard !Task.isCancelled,
                  let self,
                  isObserving,
                  interaction.revision == expectedRevision,
                  !interaction.pressedKeyCodes.isEmpty || !interaction.heldKeyCodes.isEmpty
            else {
                return
            }
            staleStateTask = nil
            clearInteraction()
        }
    }

    private func cancelStaleStateTimeout() {
        staleStateTask?.cancel()
        staleStateTask = nil
    }

    private func clearInteraction() {
        cancelStaleStateTimeout()
        guard !interaction.pressedKeyCodes.isEmpty || !interaction.heldKeyCodes.isEmpty else {
            return
        }
        var next = interaction
        next.pressedKeyCodes.removeAll()
        next.heldKeyCodes.removeAll()
        next.phase = .release
        publish(next)
    }
}
