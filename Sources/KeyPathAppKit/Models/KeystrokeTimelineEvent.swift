import Foundation

struct KeystrokeTimelineEvent: Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: EventKind

    enum EventKind {
        case keyInput(KeyInputPayload)
        case tapActivated(TapHoldPayload)
        case holdActivated(TapHoldPayload)
        case hrmDecision(HrmDecisionPayload)
        case layerChanged(LayerChangePayload)
        case oneShotActivated(OneShotPayload)
        case chordResolved(ChordPayload)
        case tapDanceResolved(TapDancePayload)
    }
}

struct KeyInputPayload {
    let key: String
    let action: KanataKeyAction
    let layer: String?
    let kanataTimestamp: UInt64?
}

struct TapHoldPayload {
    let key: String
    let outputAction: String
    let reason: String?
    let kanataTimestamp: UInt64
}

struct HrmDecisionPayload {
    let key: String
    let decision: KanataHrmDecision
    let reason: KanataHrmDecisionReason
    let decideLatencyMs: Int?
    let nextKey: String?
    let nextKeyHand: KanataHrmKeyHand?
    let configuredThresholdMs: Int?
    let isNearThreshold: Bool

    static let nearThresholdMarginMs = 30
}

struct LayerChangePayload {
    let layerName: String
}

struct OneShotPayload {
    let key: String
    let modifiers: String
}

struct ChordPayload {
    let keys: String
    let action: String
}

struct TapDancePayload {
    let key: String
    let tapCount: UInt8
    let action: String
}
