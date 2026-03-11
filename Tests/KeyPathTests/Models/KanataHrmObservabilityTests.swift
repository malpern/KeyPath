@testable import KeyPathAppKit
@preconcurrency import XCTest

final class KanataHrmObservabilityTests: XCTestCase {
    func testDecodeHrmTraceEvent() throws {
        let json = """
        {
          "schema_version": 1,
          "key": "f",
          "decision": "hold",
          "reason": "opposite-hand",
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
        XCTAssertEqual(trace.reason, .oppositeHand)
        XCTAssertEqual(trace.decideLatencyMs, 33)
        XCTAssertEqual(trace.nextKey, "j")
        XCTAssertEqual(trace.nextKeyHand, .right)
    }

    func testDecodeHrmTraceEventWithoutLatency() throws {
        let json = """
        {
          "schema_version": 1,
          "key": "a",
          "decision": "tap",
          "reason": "prior-idle"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let trace = try JSONDecoder().decode(KanataHrmTraceEvent.self, from: data)

        XCTAssertEqual(trace.key, "a")
        XCTAssertEqual(trace.decision, .tap)
        XCTAssertEqual(trace.reason, .priorIdle)
        XCTAssertNil(trace.decideLatencyMs)
    }

    func testReasonCountLookup() {
        let counts = KanataHrmReasonCounts(
            priorIdle: 1,
            releaseBeforeTimeout: 2,
            sameHandRoll: 3,
            oppositeHand: 4,
            timeout: 5,
            neutralKey: 6,
            unknownHand: 7
        )

        XCTAssertEqual(counts.count(for: .priorIdle), 1)
        XCTAssertEqual(counts.count(for: .releaseBeforeTimeout), 2)
        XCTAssertEqual(counts.count(for: .sameHandRoll), 3)
        XCTAssertEqual(counts.count(for: .oppositeHand), 4)
        XCTAssertEqual(counts.count(for: .timeout), 5)
        XCTAssertEqual(counts.count(for: .neutralKey), 6)
        XCTAssertEqual(counts.count(for: .unknownHand), 7)
    }

    func testAllKanataReasonStringsMap() {
        // Verify all 15 kanata reason strings map to enum cases
        let kanataReasons = [
            "prior-idle", "release-before-timeout", "same-hand-roll",
            "custom-tap-keys", "custom-release-trigger", "custom-tap",
            "opposite-hand", "other-key-press", "permissive-hold",
            "timeout", "release-after-timeout", "custom-hold",
            "custom-noop", "neutral-key", "unknown-hand"
        ]
        for reason in kanataReasons {
            XCTAssertNotNil(
                KanataHrmDecisionReason(rawValue: reason),
                "Missing enum case for kanata reason: \(reason)"
            )
        }
    }
}
