import Foundation

public enum KanataHrmDecision: String, Codable, Sendable, CaseIterable {
    case tap
    case hold
}

public enum KanataHrmDecisionReason: String, Codable, Sendable, CaseIterable {
    case timeout
    case releaseBeforeDecide = "release_before_decide"
    case oppositeHandKey = "opposite_hand_key"
    case sameHandKey = "same_hand_key"
    case neutralKey = "neutral_key"
    case unknownHandKey = "unknown_hand_key"
    case explicitPolicy = "explicit_policy"

    public var displayName: String {
        switch self {
        case .timeout: "Timeout"
        case .releaseBeforeDecide: "Release Before Decide"
        case .oppositeHandKey: "Opposite-Hand Key"
        case .sameHandKey: "Same-Hand Key"
        case .neutralKey: "Neutral Key"
        case .unknownHandKey: "Unknown-Hand Key"
        case .explicitPolicy: "Explicit Policy"
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
    public let timeout: Int
    public let releaseBeforeDecide: Int
    public let oppositeHandKey: Int
    public let sameHandKey: Int
    public let neutralKey: Int
    public let unknownHandKey: Int
    public let explicitPolicy: Int

    public init(
        timeout: Int = 0,
        releaseBeforeDecide: Int = 0,
        oppositeHandKey: Int = 0,
        sameHandKey: Int = 0,
        neutralKey: Int = 0,
        unknownHandKey: Int = 0,
        explicitPolicy: Int = 0
    ) {
        self.timeout = timeout
        self.releaseBeforeDecide = releaseBeforeDecide
        self.oppositeHandKey = oppositeHandKey
        self.sameHandKey = sameHandKey
        self.neutralKey = neutralKey
        self.unknownHandKey = unknownHandKey
        self.explicitPolicy = explicitPolicy
    }

    enum CodingKeys: String, CodingKey {
        case timeout
        case releaseBeforeDecide = "release_before_decide"
        case oppositeHandKey = "opposite_hand_key"
        case sameHandKey = "same_hand_key"
        case neutralKey = "neutral_key"
        case unknownHandKey = "unknown_hand_key"
        case explicitPolicy = "explicit_policy"
    }

    public func count(for reason: KanataHrmDecisionReason) -> Int {
        switch reason {
        case .timeout: timeout
        case .releaseBeforeDecide: releaseBeforeDecide
        case .oppositeHandKey: oppositeHandKey
        case .sameHandKey: sameHandKey
        case .neutralKey: neutralKey
        case .unknownHandKey: unknownHandKey
        case .explicitPolicy: explicitPolicy
        }
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
    public let decideLatencyMs: Int
    public let nextKey: String?
    public let nextKeyHand: KanataHrmKeyHand?
    public let timestamp: Date?

    public init(
        schemaVersion: Int = 1,
        key: String,
        decision: KanataHrmDecision,
        reason: KanataHrmDecisionReason,
        decideLatencyMs: Int,
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
