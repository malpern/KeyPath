import Foundation

public enum KanataHrmDecision: String, Codable, Sendable, CaseIterable {
    case tap
    case hold
}

public enum KanataHrmDecisionReason: String, Codable, Sendable, CaseIterable {
    // Tap reasons
    case priorIdle = "prior-idle"
    case releaseBeforeTimeout = "release-before-timeout"
    case sameHandRoll = "same-hand-roll"
    case customTapKeys = "custom-tap-keys"
    case customReleaseTrigger = "custom-release-trigger"
    case customTap = "custom-tap"

    // Hold reasons
    case oppositeHand = "opposite-hand"
    case otherKeyPress = "other-key-press"
    case permissiveHold = "permissive-hold"
    case timeout
    case releaseAfterTimeout = "release-after-timeout"
    case customHold = "custom-hold"

    /// Custom closure fallback
    case customNoOp = "custom-noop"

    // Neutral / edge cases
    case neutralKey = "neutral-key"
    case unknownHand = "unknown-hand"

    public var displayName: String {
        switch self {
        case .priorIdle: "Prior Idle"
        case .releaseBeforeTimeout: "Release Before Timeout"
        case .sameHandRoll: "Same-Hand Roll"
        case .customTapKeys: "Custom Tap Keys"
        case .customReleaseTrigger: "Custom Release Trigger"
        case .customTap: "Custom Tap"
        case .oppositeHand: "Opposite Hand"
        case .otherKeyPress: "Other Key Press"
        case .permissiveHold: "Permissive Hold"
        case .timeout: "Timeout"
        case .releaseAfterTimeout: "Release After Timeout"
        case .customHold: "Custom Hold"
        case .customNoOp: "Custom NoOp"
        case .neutralKey: "Neutral Key"
        case .unknownHand: "Unknown Hand"
        }
    }
}

public enum KanataHrmKeyHand: String, Codable, Sendable {
    case left
    case right
    case unknown
    case neutral
}

public struct KanataHrmReasonCounts: Codable, Sendable, Equatable {
    public let priorIdle: Int
    public let releaseBeforeTimeout: Int
    public let sameHandRoll: Int
    public let customTapKeys: Int
    public let customReleaseTrigger: Int
    public let customTap: Int
    public let oppositeHand: Int
    public let otherKeyPress: Int
    public let permissiveHold: Int
    public let timeout: Int
    public let releaseAfterTimeout: Int
    public let customHold: Int
    public let customNoOp: Int
    public let neutralKey: Int
    public let unknownHand: Int

    public init(
        priorIdle: Int = 0,
        releaseBeforeTimeout: Int = 0,
        sameHandRoll: Int = 0,
        customTapKeys: Int = 0,
        customReleaseTrigger: Int = 0,
        customTap: Int = 0,
        oppositeHand: Int = 0,
        otherKeyPress: Int = 0,
        permissiveHold: Int = 0,
        timeout: Int = 0,
        releaseAfterTimeout: Int = 0,
        customHold: Int = 0,
        customNoOp: Int = 0,
        neutralKey: Int = 0,
        unknownHand: Int = 0
    ) {
        self.priorIdle = priorIdle
        self.releaseBeforeTimeout = releaseBeforeTimeout
        self.sameHandRoll = sameHandRoll
        self.customTapKeys = customTapKeys
        self.customReleaseTrigger = customReleaseTrigger
        self.customTap = customTap
        self.oppositeHand = oppositeHand
        self.otherKeyPress = otherKeyPress
        self.permissiveHold = permissiveHold
        self.timeout = timeout
        self.releaseAfterTimeout = releaseAfterTimeout
        self.customHold = customHold
        self.customNoOp = customNoOp
        self.neutralKey = neutralKey
        self.unknownHand = unknownHand
    }

    public func count(for reason: KanataHrmDecisionReason) -> Int {
        switch reason {
        case .priorIdle: priorIdle
        case .releaseBeforeTimeout: releaseBeforeTimeout
        case .sameHandRoll: sameHandRoll
        case .customTapKeys: customTapKeys
        case .customReleaseTrigger: customReleaseTrigger
        case .customTap: customTap
        case .oppositeHand: oppositeHand
        case .otherKeyPress: otherKeyPress
        case .permissiveHold: permissiveHold
        case .timeout: timeout
        case .releaseAfterTimeout: releaseAfterTimeout
        case .customHold: customHold
        case .customNoOp: customNoOp
        case .neutralKey: neutralKey
        case .unknownHand: unknownHand
        }
    }

    enum CodingKeys: String, CodingKey {
        case priorIdle = "prior-idle"
        case releaseBeforeTimeout = "release-before-timeout"
        case sameHandRoll = "same-hand-roll"
        case customTapKeys = "custom-tap-keys"
        case customReleaseTrigger = "custom-release-trigger"
        case customTap = "custom-tap"
        case oppositeHand = "opposite-hand"
        case otherKeyPress = "other-key-press"
        case permissiveHold = "permissive-hold"
        case timeout
        case releaseAfterTimeout = "release-after-timeout"
        case customHold = "custom-hold"
        case customNoOp = "custom-noop"
        case neutralKey = "neutral-key"
        case unknownHand = "unknown-hand"
    }
}

public struct KanataHrmLatencyHistogram: Codable, Sendable, Equatable {
    public let bucket0to10: Int
    public let bucket11to25: Int
    public let bucket26to50: Int
    public let bucket51to100: Int
    public let bucket101to200: Int
    public let bucket200Plus: Int

    public init(
        bucket0to10: Int = 0,
        bucket11to25: Int = 0,
        bucket26to50: Int = 0,
        bucket51to100: Int = 0,
        bucket101to200: Int = 0,
        bucket200Plus: Int = 0
    ) {
        self.bucket0to10 = bucket0to10
        self.bucket11to25 = bucket11to25
        self.bucket26to50 = bucket26to50
        self.bucket51to100 = bucket51to100
        self.bucket101to200 = bucket101to200
        self.bucket200Plus = bucket200Plus
    }

    enum CodingKeys: String, CodingKey {
        case bucket0to10 = "bucket_0_10"
        case bucket11to25 = "bucket_11_25"
        case bucket26to50 = "bucket_26_50"
        case bucket51to100 = "bucket_51_100"
        case bucket101to200 = "bucket_101_200"
        case bucket200Plus = "bucket_200_plus"
    }
}

public struct KanataHrmStatsSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let decisionsTotal: Int
    public let tapCount: Int
    public let holdCount: Int
    public let reasonCounts: KanataHrmReasonCounts
    public let avgDecideLatencyMs: Double
    public let latencyHistogram: KanataHrmLatencyHistogram
    public let sameHandSuppressedCount: Int
    public let oppositeHandHoldCount: Int
    public let neutralDecisionsCount: Int
    public let collectedAt: Date?

    public init(
        schemaVersion: Int = 1,
        decisionsTotal: Int = 0,
        tapCount: Int = 0,
        holdCount: Int = 0,
        reasonCounts: KanataHrmReasonCounts = .init(),
        avgDecideLatencyMs: Double = 0,
        latencyHistogram: KanataHrmLatencyHistogram = .init(),
        sameHandSuppressedCount: Int = 0,
        oppositeHandHoldCount: Int = 0,
        neutralDecisionsCount: Int = 0,
        collectedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.decisionsTotal = decisionsTotal
        self.tapCount = tapCount
        self.holdCount = holdCount
        self.reasonCounts = reasonCounts
        self.avgDecideLatencyMs = avgDecideLatencyMs
        self.latencyHistogram = latencyHistogram
        self.sameHandSuppressedCount = sameHandSuppressedCount
        self.oppositeHandHoldCount = oppositeHandHoldCount
        self.neutralDecisionsCount = neutralDecisionsCount
        self.collectedAt = collectedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case decisionsTotal = "decisions_total"
        case tapCount = "tap_count"
        case holdCount = "hold_count"
        case reasonCounts = "reason_counts"
        case avgDecideLatencyMs = "avg_decide_latency_ms"
        case latencyHistogram = "latency_histogram"
        case sameHandSuppressedCount = "same_hand_suppressed_count"
        case oppositeHandHoldCount = "opposite_hand_hold_count"
        case neutralDecisionsCount = "neutral_decisions_count"
        case collectedAt
    }

    public func withCollectedAt(_ date: Date) -> KanataHrmStatsSnapshot {
        .init(
            schemaVersion: schemaVersion,
            decisionsTotal: decisionsTotal,
            tapCount: tapCount,
            holdCount: holdCount,
            reasonCounts: reasonCounts,
            avgDecideLatencyMs: avgDecideLatencyMs,
            latencyHistogram: latencyHistogram,
            sameHandSuppressedCount: sameHandSuppressedCount,
            oppositeHandHoldCount: oppositeHandHoldCount,
            neutralDecisionsCount: neutralDecisionsCount,
            collectedAt: date
        )
    }
}

public struct KanataHrmTraceEvent: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let key: String
    public let decision: KanataHrmDecision
    public let reason: KanataHrmDecisionReason
    /// Latency in ms from key press to decision. Nil when synthesized from HoldActivated/TapActivated events.
    public let decideLatencyMs: Int?
    public let nextKey: String?
    public let nextKeyHand: KanataHrmKeyHand?
    public let timestamp: Date?

    public init(
        schemaVersion: Int = 1,
        key: String,
        decision: KanataHrmDecision,
        reason: KanataHrmDecisionReason,
        decideLatencyMs: Int? = nil,
        nextKey: String? = nil,
        nextKeyHand: KanataHrmKeyHand? = nil,
        timestamp: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.key = key
        self.decision = decision
        self.reason = reason
        self.decideLatencyMs = decideLatencyMs
        self.nextKey = nextKey
        self.nextKeyHand = nextKeyHand
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case key
        case decision
        case reason
        case decideLatencyMs = "decide_latency_ms"
        case nextKey = "next_key"
        case nextKeyHand = "next_key_hand"
        case timestamp
    }

    public func withTimestamp(_ date: Date) -> KanataHrmTraceEvent {
        .init(
            schemaVersion: schemaVersion,
            key: key,
            decision: decision,
            reason: reason,
            decideLatencyMs: decideLatencyMs,
            nextKey: nextKey,
            nextKeyHand: nextKeyHand,
            timestamp: date
        )
    }
}
