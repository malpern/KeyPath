@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class HrmObservabilityServiceTests: XCTestCase {
    func testCapabilitiesNotificationMarksSupported() async {
        let center = NotificationCenter()
        let service = HrmObservabilityService.makeTestInstance(notificationCenter: center)

        center.post(
            name: .kanataCapabilitiesUpdated,
            object: nil,
            userInfo: ["capabilities": ["reload", "hrm-stats", "hrm-trace"]]
        )
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(service.availability, .supported)
        XCTAssertTrue(service.supportsHrmStats)
        XCTAssertTrue(service.supportsHrmTrace)
    }

    func testBuildRecommendationsReleaseBeforeDecideSuggestsLowerHoldDelay() {
        let service = HrmObservabilityService.makeTestInstance()
        service._testSetLatestStats(
            KanataHrmStatsSnapshot(
                schemaVersion: 1,
                decisionsTotal: 40,
                tapCount: 28,
                holdCount: 12,
                reasonCounts: KanataHrmReasonCounts(
                    timeout: 3,
                    releaseBeforeDecide: 14,
                    oppositeHandKey: 10,
                    sameHandKey: 6,
                    neutralKey: 4,
                    unknownHandKey: 2,
                    explicitPolicy: 1
                )
            )
        )
        service._testSetRecentTraceEvents([])

        let recommendations = service._testBuildRecommendations()
        let reduceHold = recommendations.first { $0.id == "reduce-hold-delay-release-before-decide" }

        XCTAssertNotNil(reduceHold)
        XCTAssertEqual(reduceHold?.holdDelayDeltaMs, -10)
    }

    func testBuildRecommendationsTimeoutSuggestsLongerWindows() {
        let service = HrmObservabilityService.makeTestInstance()
        service._testSetLatestStats(
            KanataHrmStatsSnapshot(
                schemaVersion: 1,
                decisionsTotal: 30,
                tapCount: 12,
                holdCount: 18,
                reasonCounts: KanataHrmReasonCounts(
                    timeout: 12,
                    releaseBeforeDecide: 3,
                    oppositeHandKey: 8,
                    sameHandKey: 5,
                    neutralKey: 1,
                    unknownHandKey: 1,
                    explicitPolicy: 0
                )
            )
        )
        service._testSetRecentTraceEvents([])

        let recommendations = service._testBuildRecommendations()
        let increaseHold = recommendations.first { $0.id == "increase-hold-delay-timeout" }

        XCTAssertNotNil(increaseHold)
        XCTAssertEqual(increaseHold?.holdDelayDeltaMs, 10)
        XCTAssertEqual(increaseHold?.tapWindowDeltaMs, 5)
    }

    func testBuildRecommendationsAddsPerKeyOffsetsForClusteredAccidentalReasons() {
        let service = HrmObservabilityService.makeTestInstance()
        service._testSetLatestStats(
            KanataHrmStatsSnapshot(
                schemaVersion: 1,
                decisionsTotal: 35,
                tapCount: 20,
                holdCount: 15,
                reasonCounts: KanataHrmReasonCounts(
                    timeout: 2,
                    releaseBeforeDecide: 8,
                    oppositeHandKey: 10,
                    sameHandKey: 10,
                    neutralKey: 3,
                    unknownHandKey: 2,
                    explicitPolicy: 0
                )
            )
        )
        service._testSetRecentTraceEvents(
            [
                KanataHrmTraceEvent(schemaVersion: 1, key: "f", decision: .hold, reason: .releaseBeforeDecide, decideLatencyMs: 30),
                KanataHrmTraceEvent(schemaVersion: 1, key: "f", decision: .tap, reason: .sameHandKey, decideLatencyMs: 28),
                KanataHrmTraceEvent(schemaVersion: 1, key: "f", decision: .tap, reason: .sameHandKey, decideLatencyMs: 25),
                KanataHrmTraceEvent(schemaVersion: 1, key: "j", decision: .tap, reason: .unknownHandKey, decideLatencyMs: 31),
                KanataHrmTraceEvent(schemaVersion: 1, key: "j", decision: .hold, reason: .releaseBeforeDecide, decideLatencyMs: 35),
                KanataHrmTraceEvent(schemaVersion: 1, key: "j", decision: .hold, reason: .sameHandKey, decideLatencyMs: 29)
            ]
        )

        let recommendations = service._testBuildRecommendations()
        let perKey = recommendations.first { $0.id == "per-key-tap-offset-cluster" }

        XCTAssertNotNil(perKey)
        XCTAssertEqual(perKey?.tapOffsetDeltaMsByKey["f"], 15)
        XCTAssertEqual(perKey?.tapOffsetDeltaMsByKey["j"], 15)
    }

    func testApplyRecommendationsUpdatesTimingConfig() {
        let service = HrmObservabilityService.makeTestInstance()
        service._testSetRecommendations(
            [
                .init(
                    id: "test",
                    title: "test",
                    details: "test",
                    holdDelayDeltaMs: 10,
                    tapWindowDeltaMs: -5,
                    tapOffsetDeltaMsByKey: ["f": 15],
                    holdOffsetDeltaMsByKey: ["j": 10]
                )
            ]
        )

        var config = HomeRowModsConfig()
        service.applyRecommendations(to: &config)

        XCTAssertEqual(config.timing.holdDelay, 160)
        XCTAssertEqual(config.timing.tapWindow, 195)
        XCTAssertEqual(config.timing.tapOffsets["f"], 15)
        XCTAssertEqual(config.timing.holdOffsets["j"], 10)
    }
}
