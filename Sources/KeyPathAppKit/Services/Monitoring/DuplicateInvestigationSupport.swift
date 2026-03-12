import Foundation

enum InvestigationActivationKind: String, Sendable, Equatable {
    case holdActivated = "hold-activated"
    case tapActivated = "tap-activated"
    case oneShotActivated = "one-shot-activated"
    case chordResolved = "chord-resolved"
    case tapDanceResolved = "tap-dance-resolved"
}

struct KanataObservedActivation: Sendable, Equatable {
    let kind: InvestigationActivationKind
    let key: String
    let action: String
    let kanataTimestamp: UInt64?
    let sessionID: Int
    let observedAt: Date
}

struct InvestigationHeldKey: Equatable, Sendable {
    let key: String
    let heldDurationMs: Int
}

struct InvestigationReloadSnapshot: Equatable, Sendable {
    let phase: String
    let reason: String
    let sessionID: Int?
    let observedAt: Date
    let heldKeys: [InvestigationHeldKey]
    let msSinceLastEvent: Int?
}

enum InvestigationKeyTransitionKind: String, Equatable, Sendable {
    case freshPress = "fresh-press"
    case pressWhileHeld = "press-while-held"
    case releaseAfterHold = "release-after-hold"
    case releaseWithoutTrackedPress = "release-without-tracked-press"
    case repeatWhileHeld = "repeat-while-held"
    case repeatWithoutTrackedPress = "repeat-without-tracked-press"
}

struct InvestigationKeyTransition: Equatable, Sendable {
    let key: String
    let action: KanataKeyAction
    let sessionID: Int
    let kind: InvestigationKeyTransitionKind
    let observedAt: Date
    let kanataTimestamp: UInt64?
    let sameKeyGapMs: Int?
    let heldDurationMs: Int?
    let heldKeyCount: Int
    let previousAction: KanataKeyAction?
    let previousSessionID: Int?
}

struct InvestigationActivationCorrelation: Equatable, Sendable {
    let kind: InvestigationActivationKind
    let key: String
    let action: String
    let sessionID: Int
    let observedAt: Date
    let kanataTimestamp: UInt64?
    let wasKeyHeld: Bool
    let heldKeyCount: Int
    let sameKeyGapMs: Int?
    let heldDurationMs: Int?
    let msSinceLastKeyEvent: Int?
    let previousAction: KanataKeyAction?
    let previousSessionID: Int?
}

struct InvestigationSystemKeyEvent: Equatable, Sendable {
    let key: String
    let keyCode: Int64
    let eventType: String
    let isAutorepeat: Bool
    let flagsRawValue: UInt64
    let sourcePID: Int64?
    let observedAt: Date
}

struct InvestigationSystemEventCorrelation: Equatable, Sendable {
    let key: String
    let keyCode: Int64
    let eventType: String
    let isAutorepeat: Bool
    let flagsRawValue: UInt64
    let sourcePID: Int64?
    let observedAt: Date
    let previousKanataAction: KanataKeyAction?
    let previousKanataSessionID: Int?
    let sameKeyGapMs: Int?
    let msSinceAnyKanataEvent: Int?
    let suggestsUnmatchedAutorepeat: Bool
}

actor DuplicateKeyInvestigationTracker {
    static let shared = DuplicateKeyInvestigationTracker()

    private struct TrackedEvent: Sendable {
        let action: KanataKeyAction
        let observedAt: Date
        let sessionID: Int
        let kanataTimestamp: UInt64?
    }

    private var heldKeyPressedAt: [String: Date] = [:]
    private var lastEventByKey: [String: TrackedEvent] = [:]
    private var currentSessionID: Int?
    private var lastObservedAt: Date?

    func handleSessionStart(sessionID: Int) {
        if currentSessionID != sessionID {
            heldKeyPressedAt.removeAll()
            lastEventByKey.removeAll()
        }
        currentSessionID = sessionID
    }

    func handleSessionEnd(sessionID: Int) -> InvestigationReloadSnapshot {
        let snapshot = snapshot(
            phase: "session-end",
            reason: "session=\(sessionID)",
            observedAt: Date()
        )
        heldKeyPressedAt.removeAll()
        currentSessionID = nil
        return snapshot
    }

    func record(_ event: KanataObservedKeyInput) -> InvestigationKeyTransition {
        let previous = lastEventByKey[event.key]
        // Sub-millisecond precision is intentionally truncated to integer milliseconds;
        // sufficient granularity for duplicate-key investigation timing analysis.
        let sameKeyGapMs = previous.map { Int(event.observedAt.timeIntervalSince($0.observedAt) * 1000) }
        let previousAction = previous?.action
        let previousSessionID = previous?.sessionID

        let kind: InvestigationKeyTransitionKind
        let heldDurationMs: Int?

        switch event.action {
        case .press:
            if let pressedAt = heldKeyPressedAt[event.key] {
                kind = .pressWhileHeld
                heldDurationMs = Int(event.observedAt.timeIntervalSince(pressedAt) * 1000)
            } else {
                kind = .freshPress
                heldDurationMs = nil
            }
            heldKeyPressedAt[event.key] = event.observedAt
        case .release:
            if let pressedAt = heldKeyPressedAt.removeValue(forKey: event.key) {
                kind = .releaseAfterHold
                heldDurationMs = Int(event.observedAt.timeIntervalSince(pressedAt) * 1000)
            } else {
                kind = .releaseWithoutTrackedPress
                heldDurationMs = nil
            }
        case .repeat:
            if let pressedAt = heldKeyPressedAt[event.key] {
                kind = .repeatWhileHeld
                heldDurationMs = Int(event.observedAt.timeIntervalSince(pressedAt) * 1000)
            } else {
                kind = .repeatWithoutTrackedPress
                heldDurationMs = nil
            }
        }

        currentSessionID = event.sessionID
        lastObservedAt = event.observedAt
        lastEventByKey[event.key] = TrackedEvent(
            action: event.action,
            observedAt: event.observedAt,
            sessionID: event.sessionID,
            kanataTimestamp: event.kanataTimestamp
        )

        return InvestigationKeyTransition(
            key: event.key,
            action: event.action,
            sessionID: event.sessionID,
            kind: kind,
            observedAt: event.observedAt,
            kanataTimestamp: event.kanataTimestamp,
            sameKeyGapMs: sameKeyGapMs,
            heldDurationMs: heldDurationMs,
            heldKeyCount: heldKeyPressedAt.count,
            previousAction: previousAction,
            previousSessionID: previousSessionID
        )
    }

    func snapshot(phase: String, reason: String, observedAt: Date = Date()) -> InvestigationReloadSnapshot {
        let heldKeys = heldKeyPressedAt
            .map { key, pressedAt in
                InvestigationHeldKey(
                    key: key,
                    heldDurationMs: max(0, Int(observedAt.timeIntervalSince(pressedAt) * 1000))
                )
            }
            .sorted { lhs, rhs in
                if lhs.heldDurationMs == rhs.heldDurationMs {
                    return lhs.key < rhs.key
                }
                return lhs.heldDurationMs > rhs.heldDurationMs
            }

        let msSinceLastEvent = lastObservedAt.map { max(0, Int(observedAt.timeIntervalSince($0) * 1000)) }

        return InvestigationReloadSnapshot(
            phase: phase,
            reason: reason,
            sessionID: currentSessionID,
            observedAt: observedAt,
            heldKeys: heldKeys,
            msSinceLastEvent: msSinceLastEvent
        )
    }

    func recordActivation(_ activation: KanataObservedActivation) -> InvestigationActivationCorrelation {
        let previous = lastEventByKey[activation.key]
        let sameKeyGapMs = previous.map { Int(activation.observedAt.timeIntervalSince($0.observedAt) * 1000) }
        let heldSince = heldKeyPressedAt[activation.key]
        let heldDurationMs = heldSince.map { Int(activation.observedAt.timeIntervalSince($0) * 1000) }
        let msSinceLastKeyEvent = lastObservedAt.map { Int(activation.observedAt.timeIntervalSince($0) * 1000) }

        return InvestigationActivationCorrelation(
            kind: activation.kind,
            key: activation.key,
            action: activation.action,
            sessionID: activation.sessionID,
            observedAt: activation.observedAt,
            kanataTimestamp: activation.kanataTimestamp,
            wasKeyHeld: heldSince != nil,
            heldKeyCount: heldKeyPressedAt.count,
            sameKeyGapMs: sameKeyGapMs,
            heldDurationMs: heldDurationMs,
            msSinceLastKeyEvent: msSinceLastKeyEvent,
            previousAction: previous?.action,
            previousSessionID: previous?.sessionID
        )
    }

    func recordSystemEvent(_ event: InvestigationSystemKeyEvent) -> InvestigationSystemEventCorrelation {
        let previous = lastEventByKey[event.key]
        let sameKeyGapMs = previous.map { Int(event.observedAt.timeIntervalSince($0.observedAt) * 1000) }
        let msSinceAnyKanataEvent = lastObservedAt.map { Int(event.observedAt.timeIntervalSince($0) * 1000) }

        return InvestigationSystemEventCorrelation(
            key: event.key,
            keyCode: event.keyCode,
            eventType: event.eventType,
            isAutorepeat: event.isAutorepeat,
            flagsRawValue: event.flagsRawValue,
            sourcePID: event.sourcePID,
            observedAt: event.observedAt,
            previousKanataAction: previous?.action,
            previousKanataSessionID: previous?.sessionID,
            sameKeyGapMs: sameKeyGapMs,
            msSinceAnyKanataEvent: msSinceAnyKanataEvent,
            suggestsUnmatchedAutorepeat: event.isAutorepeat && previous?.action != .repeat
        )
    }
}

enum DuplicateInvestigationSupport {
    static let envKey = "KEYPATH_DUPLICATE_INVESTIGATION"

    static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if let raw = environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch raw {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                break
            }
        }

        #if DEBUG
            return true
        #else
            return false
        #endif
    }

    static func sessionRelation(previous: Int?, current: Int?) -> String {
        switch (previous, current) {
        case let (lhs?, rhs?) where lhs == rhs:
            "same-session"
        case (_?, _?):
            "cross-session"
        default:
            "unknown-session"
        }
    }

    static func makeSessionBoundaryLog(sessionID: Int, port: Int, connectedAt: Date) -> String {
        "[INVESTIGATION] EventListener session_start session=\(sessionID) port=\(port) connected_at=\(iso8601(connectedAt))"
    }

    static func makeReconnectLog(sessionID: Int?, errorDescription: String) -> String {
        let sessionComponent = sessionID.map { "session=\($0)" } ?? "session=none"
        return "[INVESTIGATION] EventListener reconnect_pending \(sessionComponent) error=\(sanitize(errorDescription))"
    }

    static func makeSessionEndLog(sessionID: Int, reason: String, endedAt: Date) -> String {
        "[INVESTIGATION] EventListener session_end session=\(sessionID) reason=\(sanitize(reason)) ended_at=\(iso8601(endedAt))"
    }

    static func makeObservedKeyInputLog(_ event: KanataObservedKeyInput) -> String {
        let tComponent = event.kanataTimestamp.map { " kanata_t=\($0)" } ?? ""
        return "[INVESTIGATION] EventListener key_input session=\(event.sessionID) observed_at=\(iso8601(event.observedAt)) key=\(event.key) action=\(event.action.rawValue)\(tComponent)"
    }

    static func makeKeyTransitionLog(_ transition: InvestigationKeyTransition) -> String {
        let kanataComponent = transition.kanataTimestamp.map { " kanata_t=\($0)" } ?? ""
        let gapComponent = transition.sameKeyGapMs.map { " same_key_gap_ms=\($0)" } ?? ""
        let holdComponent = transition.heldDurationMs.map { " held_duration_ms=\($0)" } ?? ""
        let previousAction = transition.previousAction?.rawValue ?? "none"
        let previousSession = transition.previousSessionID.map(String.init) ?? "none"
        return "[INVESTIGATION] KeyTransition session=\(transition.sessionID) observed_at=\(iso8601(transition.observedAt)) key=\(transition.key) action=\(transition.action.rawValue) kind=\(transition.kind.rawValue) previous_action=\(previousAction) previous_session=\(previousSession) held_key_count=\(transition.heldKeyCount)\(gapComponent)\(holdComponent)\(kanataComponent)"
    }

    static func makeReloadBoundaryLog(_ snapshot: InvestigationReloadSnapshot) -> String {
        let sessionComponent = snapshot.sessionID.map(String.init) ?? "none"
        let lastEventComponent = snapshot.msSinceLastEvent.map { " ms_since_last_key_event=\($0)" } ?? ""
        let heldKeysComponent = snapshot.heldKeys.isEmpty
            ? "held_keys=none"
            : "held_keys=\(snapshot.heldKeys.map { "\($0.key):\($0.heldDurationMs)ms" }.joined(separator: ","))"
        return "[INVESTIGATION] ReloadBoundary phase=\(sanitize(snapshot.phase)) reason=\(sanitize(snapshot.reason)) session=\(sessionComponent) observed_at=\(iso8601(snapshot.observedAt)) held_key_count=\(snapshot.heldKeys.count) \(heldKeysComponent)\(lastEventComponent)"
    }

    static func makeActivationLog(_ correlation: InvestigationActivationCorrelation) -> String {
        let kanataComponent = correlation.kanataTimestamp.map { " kanata_t=\($0)" } ?? ""
        let gapComponent = correlation.sameKeyGapMs.map { " same_key_gap_ms=\($0)" } ?? ""
        let heldDurationComponent = correlation.heldDurationMs.map { " held_duration_ms=\($0)" } ?? ""
        let lastEventComponent = correlation.msSinceLastKeyEvent.map { " ms_since_last_key_event=\($0)" } ?? ""
        let previousAction = correlation.previousAction?.rawValue ?? "none"
        let previousSession = correlation.previousSessionID.map(String.init) ?? "none"
        return "[INVESTIGATION] Activation kind=\(correlation.kind.rawValue) session=\(correlation.sessionID) observed_at=\(iso8601(correlation.observedAt)) key=\(correlation.key) action=\(sanitize(correlation.action)) was_key_held=\(correlation.wasKeyHeld) held_key_count=\(correlation.heldKeyCount) previous_action=\(previousAction) previous_session=\(previousSession)\(gapComponent)\(heldDurationComponent)\(lastEventComponent)\(kanataComponent)"
    }

    static func makeCorrelationLog(
        state: String,
        key: String,
        action: String,
        previous: KeypressObservationMetadata?,
        current: KeypressObservationMetadata,
        currentTimestamp: Date,
        windowMs: Int?
    ) -> String {
        let relation = sessionRelation(previous: previous?.listenerSessionID, current: current.listenerSessionID)
        let previousSession = previous?.listenerSessionID.map(String.init) ?? "none"
        let currentSession = current.listenerSessionID.map(String.init) ?? "none"
        let currentKanata = current.kanataTimestamp.map(String.init) ?? "none"
        let previousKanata = previous?.kanataTimestamp.map(String.init) ?? "none"
        let windowComponent = windowMs.map { " dedup_window_ms=\($0)" } ?? ""
        let previousObserved = previous?.observedAt.map(iso8601) ?? "none"

        return "[INVESTIGATION] KeyObservation state=\(sanitize(state)) relation=\(relation) key=\(key) action=\(action) current_session=\(currentSession) previous_session=\(previousSession) current_observed_at=\(iso8601(currentTimestamp)) previous_observed_at=\(previousObserved) current_kanata_t=\(currentKanata) previous_kanata_t=\(previousKanata)\(windowComponent)"
    }

    static func makeSystemKeyEventLog(_ correlation: InvestigationSystemEventCorrelation) -> String {
        let previousAction = correlation.previousKanataAction?.rawValue ?? "none"
        let previousSession = correlation.previousKanataSessionID.map(String.init) ?? "none"
        let sameKeyGap = correlation.sameKeyGapMs.map { " same_key_gap_ms=\($0)" } ?? ""
        let sinceAnyKanata = correlation.msSinceAnyKanataEvent.map { " ms_since_any_kanata_event=\($0)" } ?? ""
        let sourcePID = correlation.sourcePID.map(String.init) ?? "none"
        let unmatchedAutorepeat = " suggests_unmatched_autorepeat=\(correlation.suggestsUnmatchedAutorepeat)"

        return "[INVESTIGATION] SystemKeyEvent observed_at=\(iso8601(correlation.observedAt)) event_type=\(sanitize(correlation.eventType)) key=\(correlation.key) key_code=\(correlation.keyCode) is_autorepeat=\(correlation.isAutorepeat) flags=0x\(String(correlation.flagsRawValue, radix: 16)) source_pid=\(sourcePID) previous_kanata_action=\(previousAction) previous_kanata_session=\(previousSession)\(sameKeyGap)\(sinceAnyKanata)\(unmatchedAutorepeat)"
    }

    static func makeAutorepeatMismatchLog(_ correlation: InvestigationSystemEventCorrelation) -> String {
        let previousAction = correlation.previousKanataAction?.rawValue ?? "none"
        let previousSession = correlation.previousKanataSessionID.map(String.init) ?? "none"
        let sameKeyGap = correlation.sameKeyGapMs.map { " same_key_gap_ms=\($0)" } ?? ""
        let sinceAnyKanata = correlation.msSinceAnyKanataEvent.map { " ms_since_any_kanata_event=\($0)" } ?? ""

        return "[INVESTIGATION] AutorepeatMismatch observed_at=\(iso8601(correlation.observedAt)) key=\(correlation.key) key_code=\(correlation.keyCode) previous_kanata_action=\(previousAction) previous_kanata_session=\(previousSession)\(sameKeyGap)\(sinceAnyKanata)"
    }

    private static let keyMap: [Int64: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "return",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space",
        50: "`", 51: "delete", 53: "escape", 54: "rmet", 55: "lmet",
        56: "lsft", 57: "caps", 58: "lalt", 59: "lctl", 60: "rsft",
        61: "ralt", 62: "rctl", 63: "fn", 64: "f17", 65: "kp-decimal",
        67: "kp-multiply", 69: "kp-plus", 71: "kp-clear", 75: "kp-divide",
        76: "kp-enter", 78: "kp-minus", 81: "kp-equals", 82: "kp-0",
        83: "kp-1", 84: "kp-2", 85: "kp-3", 86: "kp-4", 87: "kp-5",
        88: "kp-6", 89: "kp-7", 91: "kp-8", 92: "kp-9", 96: "f5",
        97: "f6", 98: "f7", 99: "f3", 100: "f8", 101: "f9", 103: "f11",
        105: "f13", 106: "f16", 107: "f14", 109: "f10", 111: "f12",
        113: "f15", 114: "help", 115: "home", 116: "pageup", 117: "forwarddelete",
        118: "f4", 119: "end", 120: "f2", 121: "pagedown", 122: "f1",
        123: "left", 124: "right", 125: "down", 126: "up"
    ]

    static func keyName(forKeyCode keyCode: Int64) -> String {
        keyMap[keyCode] ?? "keycode-\(keyCode)"
    }

    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func iso8601(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    private static func sanitize(_ string: String) -> String {
        string.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }
}
