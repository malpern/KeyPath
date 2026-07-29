import Foundation

public enum CaptureRunState: String, Codable, Sendable {
    case idle
    case armed
    case capturing
    case passed
    case failed
}

public enum CapturedEventPhase: String, Codable, Sendable {
    case down
    case up
    case flagsChanged
}

public struct CapturedKeyEvent: Codable, Equatable, Sendable {
    public let sequence: Int
    public let phase: CapturedEventPhase
    public let keyCode: UInt16
    public let characters: String
    public let modifiers: UInt
    public let isRepeat: Bool
    public let timestampNs: UInt64

    public init(
        sequence: Int,
        phase: CapturedEventPhase,
        keyCode: UInt16,
        characters: String,
        modifiers: UInt,
        isRepeat: Bool,
        timestampNs: UInt64
    ) {
        self.sequence = sequence
        self.phase = phase
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.timestampNs = timestampNs
    }
}

public struct CaptureSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runID: String
    public let state: CaptureRunState
    public let focused: Bool
    public let expected: String
    public let received: String
    public let issues: [String]
    public let events: [CapturedKeyEvent]
    public let pressedKeyCodes: [UInt16]
    public let activeModifiers: UInt
    public let repeatEvents: Int
    public let duplicateDownEvents: Int
    public let unmatchedUpEvents: Int
    public let startedAtNs: UInt64?
    public let firstEventAtNs: UInt64?
    public let lastEventAtNs: UInt64?
    public let deadlineAtNs: UInt64?
    public let settledForMs: UInt64

    public var exactMatch: Bool {
        received == expected
    }

    public var allKeysReleased: Bool {
        pressedKeyCodes.isEmpty && activeModifiers == 0
    }
}

public final class CaptureSession {
    private var runID = ""
    private var state: CaptureRunState = .idle
    private var focused = false
    private var expected = ""
    private var received = ""
    private var events: [CapturedKeyEvent] = []
    private var pressedKeyCodes: Set<UInt16> = []
    private var activeModifiers: UInt = 0
    private var repeatEvents = 0
    private var duplicateDownEvents = 0
    private var unmatchedUpEvents = 0
    private var focusLost = false
    private var finalized = false
    private var terminalFailure = false
    private var startedAtNs: UInt64?
    private var firstEventAtNs: UInt64?
    private var lastEventAtNs: UInt64?
    private var deadlineAtNs: UInt64?
    private var settleNs: UInt64 = 250_000_000

    public init() {}

    public func reset() {
        runID = ""
        state = .idle
        focused = false
        expected = ""
        received = ""
        events.removeAll(keepingCapacity: true)
        pressedKeyCodes.removeAll(keepingCapacity: true)
        activeModifiers = 0
        repeatEvents = 0
        duplicateDownEvents = 0
        unmatchedUpEvents = 0
        focusLost = false
        finalized = false
        terminalFailure = false
        startedAtNs = nil
        firstEventAtNs = nil
        lastEventAtNs = nil
        deadlineAtNs = nil
    }

    @discardableResult
    public func arm(
        runID: String,
        expected: String,
        timeoutMs: UInt64,
        settleMs: UInt64,
        focused: Bool,
        nowNs: UInt64
    ) -> Bool {
        reset()
        guard !runID.isEmpty, runID.count <= 80, !expected.isEmpty,
              timeoutMs >= 250, timeoutMs <= 300_000,
              settleMs >= 50, settleMs <= 5000,
              focused
        else {
            self.runID = runID
            self.expected = expected
            self.focused = focused
            state = .failed
            return false
        }
        self.runID = runID
        self.expected = Self.normalize(expected)
        self.focused = true
        startedAtNs = nowNs
        deadlineAtNs = nowNs &+ timeoutMs &* 1_000_000
        settleNs = settleMs &* 1_000_000
        state = .armed
        return true
    }

    public func noteFocus(_ focused: Bool, nowNs: UInt64) {
        self.focused = focused
        if !focused, state == .capturing {
            focusLost = true
            terminalFailure = true
            state = .failed
            lastEventAtNs = nowNs
        }
    }

    public func record(
        phase: CapturedEventPhase,
        keyCode: UInt16,
        characters: String,
        modifiers: UInt,
        isRepeat: Bool,
        nowNs: UInt64
    ) {
        guard state != .idle, !runID.isEmpty else { return }
        let normalized = phase == .down ? Self.normalize(characters) : ""
        events.append(CapturedKeyEvent(
            sequence: events.count + 1,
            phase: phase,
            keyCode: keyCode,
            characters: normalized,
            modifiers: modifiers,
            isRepeat: isRepeat,
            timestampNs: nowNs
        ))
        if firstEventAtNs == nil {
            firstEventAtNs = nowNs
        }
        lastEventAtNs = nowNs
        activeModifiers = modifiers

        switch phase {
        case .down:
            if !pressedKeyCodes.insert(keyCode).inserted {
                duplicateDownEvents += 1
            }
            if isRepeat {
                repeatEvents += 1
            }
            received.append(normalized)
        case .up:
            if pressedKeyCodes.remove(keyCode) == nil {
                unmatchedUpEvents += 1
            }
        case .flagsChanged:
            break
        }

        if state != .failed {
            state = .capturing
        }
        evaluate(nowNs: nowNs)
    }

    public func finalize(nowNs: UInt64) {
        guard state != .idle else { return }
        finalized = true
        evaluate(nowNs: nowNs)
    }

    public func snapshot(nowNs: UInt64) -> CaptureSnapshot {
        evaluate(nowNs: nowNs)
        let settledForNs = lastEventAtNs.map { nowNs >= $0 ? nowNs - $0 : 0 } ?? 0
        return CaptureSnapshot(
            schemaVersion: 1,
            runID: runID,
            state: state,
            focused: focused,
            expected: expected,
            received: received,
            issues: issues(nowNs: nowNs),
            events: events,
            pressedKeyCodes: pressedKeyCodes.sorted(),
            activeModifiers: activeModifiers,
            repeatEvents: repeatEvents,
            duplicateDownEvents: duplicateDownEvents,
            unmatchedUpEvents: unmatchedUpEvents,
            startedAtNs: startedAtNs,
            firstEventAtNs: firstEventAtNs,
            lastEventAtNs: lastEventAtNs,
            deadlineAtNs: deadlineAtNs,
            settledForMs: settledForNs / 1_000_000
        )
    }

    private func evaluate(nowNs: UInt64) {
        guard state != .idle else { return }
        if terminalFailure {
            state = .failed
            return
        }
        if focusLost || repeatEvents > 0 || duplicateDownEvents > 0 || unmatchedUpEvents > 0 ||
            mismatchIndex() != nil || received.count > expected.count
        {
            terminalFailure = true
            state = .failed
            return
        }
        let timedOut = deadlineAtNs.map { nowNs >= $0 } ?? false
        if timedOut || finalized {
            if received == expected, pressedKeyCodes.isEmpty, activeModifiers == 0 {
                state = .passed
            } else {
                terminalFailure = true
                state = .failed
            }
            return
        }
        if received == expected, pressedKeyCodes.isEmpty, activeModifiers == 0,
           let lastEventAtNs, nowNs >= lastEventAtNs,
           nowNs - lastEventAtNs >= settleNs
        {
            state = .passed
        }
    }

    private func issues(nowNs: UInt64) -> [String] {
        var result: [String] = []
        if focusLost {
            result.append("capture focus was lost")
        }
        if repeatEvents > 0 {
            result.append("received \(repeatEvents) repeated key-down event(s)")
        }
        if duplicateDownEvents > 0 {
            result.append("received \(duplicateDownEvents) key-down event(s) before release")
        }
        if unmatchedUpEvents > 0 {
            result.append("received \(unmatchedUpEvents) key-up event(s) without a matching key-down")
        }
        if let index = mismatchIndex() {
            result.append("received output differs from expected output at character \(index)")
        }
        if received.count > expected.count {
            result.append("received \(received.count - expected.count) extra character(s)")
        }
        let terminal = finalized || (deadlineAtNs.map { nowNs >= $0 } ?? false)
        if terminal, !focused, firstEventAtNs == nil {
            result.append("capture was not focused before input arrived")
        }
        if terminal, received.count < expected.count {
            result.append("missing \(expected.count - received.count) expected character(s)")
        }
        if terminal, !pressedKeyCodes.isEmpty {
            result.append("unreleased key code(s): \(pressedKeyCodes.sorted())")
        }
        if terminal, activeModifiers != 0 {
            result.append("unreleased modifier flags: \(activeModifiers)")
        }
        return result
    }

    private func mismatchIndex() -> Int? {
        let actual = Array(received)
        let target = Array(expected)
        for index in 0 ..< min(actual.count, target.count) where actual[index] != target[index] {
            return index
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "\n")
    }
}
