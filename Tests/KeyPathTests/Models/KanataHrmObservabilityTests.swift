@testable import KeyPathAppKit
@preconcurrency import XCTest

final class KanataHrmObservabilityTests: XCTestCase {
    func testDecodeHrmStatsSnapshot() throws {
        let json = """
        {
          "schema_version": 1,
          "decisions_total": 17,
          "tap_count": 10,
          "hold_count": 7,
          "reason_counts": {
            "timeout": 2,
            "release_before_decide": 3,
            "opposite_hand_key": 6,
            "same_hand_key": 4,
            "neutral_key": 1,
            "unknown_hand_key": 1,
            "explicit_policy": 0
          },
          "avg_decide_latency_ms": 41.2,
          "latency_histogram": {
            "bucket_0_10": 3,
            "bucket_11_25": 4,
            "bucket_26_50": 6,
            "bucket_51_100": 3,
            "bucket_101_200": 1,
            "bucket_200_plus": 0
          },
          "same_hand_suppressed_count": 4,
          "opposite_hand_hold_count": 6,
          "neutral_decisions_count": 1
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(KanataHrmStatsSnapshot.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.decisionsTotal, 17)
        XCTAssertEqual(snapshot.tapCount, 10)
        XCTAssertEqual(snapshot.holdCount, 7)
        XCTAssertEqual(snapshot.reasonCounts.releaseBeforeDecide, 3)
        XCTAssertEqual(snapshot.reasonCounts.oppositeHandKey, 6)
        XCTAssertEqual(snapshot.avgDecideLatencyMs, 41.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.latencyHistogram.bucket26to50, 6)
        XCTAssertEqual(snapshot.sameHandSuppressedCount, 4)
        XCTAssertEqual(snapshot.oppositeHandHoldCount, 6)
        XCTAssertEqual(snapshot.neutralDecisionsCount, 1)
    }

    func testDecodeHrmTraceEvent() throws {
        let json = """
        {
          "schema_version": 1,
          "key": "f",
          "decision": "hold",
          "reason": "opposite_hand_key",
          "decide_latency_ms": 33,
          "next_key": "j",
          "next_key_hand": "right"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let trace = try JSONDecoder().decode(KanataHrmTraceEvent.self, from: data)

        XCTAssertEqual(trace.schemaVersion, 1)
        XCTAssertEqual(trace.key, "f")
        XCTAssertEqual(trace.decision, .hold)
        XCTAssertEqual(trace.reason, .oppositeHandKey)
        XCTAssertEqual(trace.decideLatencyMs, 33)
        XCTAssertEqual(trace.nextKey, "j")
        XCTAssertEqual(trace.nextKeyHand, .right)
    }

    func testReasonCountLookup() {
        let counts = KanataHrmReasonCounts(
            timeout: 1,
            releaseBeforeDecide: 2,
            oppositeHandKey: 3,
            sameHandKey: 4,
            neutralKey: 5,
            unknownHandKey: 6,
            explicitPolicy: 7
        )

        XCTAssertEqual(counts.count(for: .timeout), 1)
        XCTAssertEqual(counts.count(for: .releaseBeforeDecide), 2)
        XCTAssertEqual(counts.count(for: .oppositeHandKey), 3)
        XCTAssertEqual(counts.count(for: .sameHandKey), 4)
        XCTAssertEqual(counts.count(for: .neutralKey), 5)
        XCTAssertEqual(counts.count(for: .unknownHandKey), 6)
        XCTAssertEqual(counts.count(for: .explicitPolicy), 7)
    }
}
