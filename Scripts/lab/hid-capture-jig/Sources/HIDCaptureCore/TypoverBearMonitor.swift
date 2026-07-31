import Foundation

public enum TypoverBearMonitorPhase: String, Codable, Equatable, Sendable {
    case inactive
    case preparing
    case waitingForBear
    case countdown
    case typing
    case analyzing
    case passed
    case safeMisses
    case failed
}

public struct TypoverBearMonitorSnapshot: Codable, Equatable, Sendable {
    public let phase: TypoverBearMonitorPhase
    public let runID: String
    public let caseIndex: Int
    public let caseCount: Int
    public let intervalMs: Int
    public let wordCount: Int
    public let scheduledText: String
    public let scheduledStartAtNs: UInt64?
    public let scheduledEvents: [CapturedKeyEvent]
    public let correctedWords: Int
    public let missedWords: Int
    public let message: String
    public let bearFocused: Bool

    public var isActive: Bool {
        phase != .inactive
    }

    public var totalKeyPresses: Int {
        scheduledText.count
    }

    public var presentedKeyPresses: Int {
        scheduledEvents.count
    }

    public var completion: Double {
        guard totalKeyPresses > 0 else { return 0 }
        return min(1, Double(presentedKeyPresses) / Double(totalKeyPresses))
    }

    public var keysPerSecond: Double {
        intervalMs > 0 ? 1000 / Double(intervalMs) : 0
    }
}

public final class TypoverBearMonitorSession {
    private var phase = TypoverBearMonitorPhase.inactive
    private var runID = ""
    private var caseIndex = 0
    private var caseCount = 0
    private var intervalMs = 0
    private var wordCount = 0
    private var scheduledText = ""
    private var scheduledStartAtNs: UInt64?
    private var correctedWords = 0
    private var missedWords = 0
    private var message = ""
    private var bearFocused = false

    public init() {}

    @discardableResult
    public func prepare(
        runID: String,
        caseCount: Int,
        message: String,
        nowNs _: UInt64
    ) -> Bool {
        guard !runID.isEmpty, runID.count <= 80,
              (1 ... 100).contains(caseCount)
        else { return false }
        reset()
        self.runID = runID
        self.caseCount = caseCount
        self.message = String(message.prefix(240))
        phase = .waitingForBear
        return true
    }

    @discardableResult
    public func begin(
        runID: String,
        caseIndex: Int,
        caseCount: Int,
        intervalMs: Int,
        wordCount: Int,
        scheduledText: String,
        startDelayMs: Int,
        bearFocused: Bool,
        nowNs: UInt64
    ) -> Bool {
        guard !runID.isEmpty, runID.count <= 80,
              caseIndex >= 1, caseCount >= caseIndex, caseCount <= 100,
              (4 ... 2000).contains(intervalMs),
              (1 ... 100).contains(wordCount),
              !scheduledText.isEmpty, scheduledText.count <= 512,
              scheduledText.unicodeScalars.allSatisfy(\.isASCII),
              (100 ... 60000).contains(startDelayMs)
        else { return false }

        self.runID = runID
        self.caseIndex = caseIndex
        self.caseCount = caseCount
        self.intervalMs = intervalMs
        self.wordCount = wordCount
        self.scheduledText = scheduledText
        scheduledStartAtNs = nowNs &+ UInt64(startDelayMs) &* 1_000_000
        correctedWords = 0
        missedWords = 0
        message = "Bear owns keyboard focus"
        self.bearFocused = bearFocused
        phase = .countdown
        return true
    }

    @discardableResult
    public func update(
        phase: TypoverBearMonitorPhase,
        correctedWords: Int? = nil,
        missedWords: Int? = nil,
        message: String? = nil,
        bearFocused: Bool? = nil
    ) -> Bool {
        guard self.phase != .inactive, phase != .inactive else { return false }
        let nextCorrected = correctedWords ?? self.correctedWords
        let nextMissed = missedWords ?? self.missedWords
        guard nextCorrected >= 0, nextMissed >= 0,
              nextCorrected + nextMissed <= wordCount
        else { return false }
        self.phase = phase
        self.correctedWords = nextCorrected
        self.missedWords = nextMissed
        if let message {
            self.message = String(message.prefix(240))
        }
        if let bearFocused {
            self.bearFocused = bearFocused
        }
        return true
    }

    public func reset() {
        phase = .inactive
        runID = ""
        caseIndex = 0
        caseCount = 0
        intervalMs = 0
        wordCount = 0
        scheduledText = ""
        scheduledStartAtNs = nil
        correctedWords = 0
        missedWords = 0
        message = ""
        bearFocused = false
    }

    public func snapshot(nowNs: UInt64) -> TypoverBearMonitorSnapshot {
        TypoverBearMonitorSnapshot(
            phase: phase,
            runID: runID,
            caseIndex: caseIndex,
            caseCount: caseCount,
            intervalMs: intervalMs,
            wordCount: wordCount,
            scheduledText: scheduledText,
            scheduledStartAtNs: scheduledStartAtNs,
            scheduledEvents: scheduledEvents(nowNs: nowNs),
            correctedWords: correctedWords,
            missedWords: missedWords,
            message: message,
            bearFocused: bearFocused
        )
    }

    private func scheduledEvents(nowNs: UInt64) -> [CapturedKeyEvent] {
        guard phase != .inactive, let scheduledStartAtNs,
              nowNs >= scheduledStartAtNs
        else { return [] }
        let intervalNs = UInt64(intervalMs) * 1_000_000
        let elapsed = nowNs - scheduledStartAtNs
        let count = min(scheduledText.count, Int(elapsed / intervalNs) + 1)
        return Array(scheduledText.prefix(count)).enumerated().map { index, character in
            CapturedKeyEvent(
                sequence: index + 1,
                phase: .down,
                keyCode: Self.keyCode(for: character),
                characters: String(character),
                modifiers: 0,
                isRepeat: false,
                timestampNs: scheduledStartAtNs &+ UInt64(index) &* intervalNs
            )
        }
    }

    private static func keyCode(for character: Character) -> UInt16 {
        switch character {
        case "t": 17
        case "e": 14
        case "h": 4
        case " ": 49
        case "\n", "\r": 36
        default: 0
        }
    }
}
