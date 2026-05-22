import Foundation

// MARK: - Segment Types

enum TimelineSegment: Identifiable {
    case textRun(TextRunSegment)
    case eventCard(EventCardSegment)
    case layerDivider(LayerDividerSegment)

    var id: UUID {
        switch self {
        case let .textRun(s): s.id
        case let .eventCard(s): s.id
        case let .layerDivider(s): s.id
        }
    }

    var timestamp: Date {
        switch self {
        case let .textRun(s): s.characters.first?.timestamp ?? Date()
        case let .eventCard(s): s.timestamp
        case let .layerDivider(s): s.timestamp
        }
    }
}

struct TextRunSegment: Identifiable {
    let id = UUID()
    let characters: [TextRunCharacter]
}

struct TextRunCharacter: Identifiable {
    let id: UUID
    let displayChar: String
    let rawKey: String
    let timestamp: Date
    let layer: String?
    let kanataTimestamp: UInt64?
}

struct EventCardSegment: Identifiable {
    let id: UUID
    let timestamp: Date
    let cardKind: EventCardKind
}

enum EventCardKind {
    case tapHold(TapHoldCardData)
    case hrmDecision(HrmCardData)
    case oneShot(OneShotPayload)
    case chord(ChordPayload)
    case tapDance(TapDancePayload)
    case nonPrintableKey(key: String, action: KanataKeyAction)
}

struct TapHoldCardData {
    let key: String
    let outputAction: String
    let reason: String?
    let isHold: Bool
}

struct HrmCardData {
    let key: String
    let decision: KanataHrmDecision
    let reason: KanataHrmDecisionReason
    let decideLatencyMs: Int?
    let configuredThresholdMs: Int?
    let isNearThreshold: Bool
    let nextKey: String?
}

struct LayerDividerSegment: Identifiable {
    let id = UUID()
    let timestamp: Date
    let layerName: String
}

// MARK: - Grouper

enum TimelineGrouper {
    private static let printableKeys: [String: String] = {
        var map: [String: String] = [:]
        for c in "abcdefghijklmnopqrstuvwxyz" {
            map[String(c)] = String(c)
        }
        for i in 0 ... 9 {
            map["\(i)"] = "\(i)"
        }
        map["spc"] = " "
        map["space"] = " "
        map["min"] = "-"
        map["minus"] = "-"
        map["eql"] = "="
        map["equal"] = "="
        map["lbrc"] = "["
        map["rbrc"] = "]"
        map["bksl"] = "\\"
        map["scln"] = ";"
        map["apos"] = "'"
        map["apostrophe"] = "'"
        map["grv"] = "`"
        map["grave"] = "`"
        map["comm"] = ","
        map["dot"] = "."
        map["slsh"] = "/"
        map["slash"] = "/"
        map["tab"] = "⇥"
        return map
    }()

    private static let modifierKeys: Set<String> = [
        "lsft", "rsft", "lctl", "rctl", "lalt", "ralt", "lmet", "rmet",
        "leftshift", "rightshift", "leftctrl", "rightctrl",
        "leftalt", "rightalt", "leftmeta", "rightmeta",
        "lshift", "rshift",
    ]

    static func group(_ events: [KeystrokeTimelineEvent], currentLayer _: String) -> [TimelineSegment] {
        var segments: [TimelineSegment] = []
        var currentTextRun: [TextRunCharacter] = []

        func flushTextRun() {
            guard !currentTextRun.isEmpty else { return }
            segments.append(.textRun(TextRunSegment(characters: currentTextRun)))
            currentTextRun = []
        }

        for event in events {
            switch event.kind {
            case let .keyInput(payload):
                guard payload.action == .press else { continue }

                if modifierKeys.contains(payload.key.lowercased()) {
                    continue
                }

                if let displayChar = printableKeys[payload.key.lowercased()] {
                    currentTextRun.append(TextRunCharacter(
                        id: event.id,
                        displayChar: displayChar,
                        rawKey: payload.key,
                        timestamp: event.timestamp,
                        layer: payload.layer,
                        kanataTimestamp: payload.kanataTimestamp
                    ))
                } else {
                    flushTextRun()
                    segments.append(.eventCard(EventCardSegment(
                        id: event.id,
                        timestamp: event.timestamp,
                        cardKind: .nonPrintableKey(key: payload.key, action: payload.action)
                    )))
                }

            case let .layerChanged(payload):
                flushTextRun()
                segments.append(.layerDivider(LayerDividerSegment(
                    timestamp: event.timestamp,
                    layerName: payload.layerName
                )))

            case let .tapActivated(payload):
                flushTextRun()
                segments.append(.eventCard(EventCardSegment(
                    id: event.id,
                    timestamp: event.timestamp,
                    cardKind: .tapHold(TapHoldCardData(
                        key: payload.key,
                        outputAction: payload.outputAction,
                        reason: payload.reason,
                        isHold: false
                    ))
                )))

            case let .holdActivated(payload):
                flushTextRun()
                segments.append(.eventCard(EventCardSegment(
                    id: event.id,
                    timestamp: event.timestamp,
                    cardKind: .tapHold(TapHoldCardData(
                        key: payload.key,
                        outputAction: payload.outputAction,
                        reason: payload.reason,
                        isHold: true
                    ))
                )))

            case let .hrmDecision(payload):
                flushTextRun()
                segments.append(.eventCard(EventCardSegment(
                    id: event.id,
                    timestamp: event.timestamp,
                    cardKind: .hrmDecision(HrmCardData(
                        key: payload.key,
                        decision: payload.decision,
                        reason: payload.reason,
                        decideLatencyMs: payload.decideLatencyMs,
                        configuredThresholdMs: payload.configuredThresholdMs,
                        isNearThreshold: payload.isNearThreshold,
                        nextKey: payload.nextKey
                    ))
                )))

            case let .oneShotActivated(payload):
                flushTextRun()
                segments.append(.eventCard(EventCardSegment(
                    id: event.id,
                    timestamp: event.timestamp,
                    cardKind: .oneShot(payload)
                )))

            case let .chordResolved(payload):
                flushTextRun()
                segments.append(.eventCard(EventCardSegment(
                    id: event.id,
                    timestamp: event.timestamp,
                    cardKind: .chord(payload)
                )))

            case let .tapDanceResolved(payload):
                flushTextRun()
                segments.append(.eventCard(EventCardSegment(
                    id: event.id,
                    timestamp: event.timestamp,
                    cardKind: .tapDance(payload)
                )))
            }
        }

        flushTextRun()
        return segments
    }
}
