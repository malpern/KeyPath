@testable import KeyPathAppKit
import XCTest

/// Pure-data assertions on the insight rule engine. No file I/O, no
/// singletons — every test builds a fixture snapshot and reads back
/// the engine's output.
final class VimInsightsEngineTests: XCTestCase {
    // MARK: - Stage classification

    func testStageIsUnknownBelowSampleFloor() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 5, "j": 5]  // total 10 → below floor of 50
        XCTAssertEqual(VimInsightsEngine.stage(for: snap), .unknown)
    }

    func testStageIsBeginnerWhenArrowsDominate() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 10, "j": 10]
        snap.nonVimNavigationFrequency = ["left": 50, "right": 50]
        // 100 arrows / 120 total = 83% → beginner
        XCTAssertEqual(VimInsightsEngine.stage(for: snap), .beginner)
    }

    func testStageIsIntermediateInTheMiddle() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 30, "j": 30, "k": 20, "l": 20]  // 100 hjkl
        snap.nonVimNavigationFrequency = ["left": 25]
        // 25 / 125 = 20% → intermediate
        XCTAssertEqual(VimInsightsEngine.stage(for: snap), .intermediate)
    }

    func testStageIsAdvancedWhenArrowsAreRare() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 100, "j": 100, "k": 100, "l": 100]
        snap.nonVimNavigationFrequency = ["left": 30]
        // 30 / 430 ≈ 7% → advanced
        XCTAssertEqual(VimInsightsEngine.stage(for: snap), .advanced)
    }

    // MARK: - Headline metric

    func testArrowReliancePercentNilWithNoData() {
        XCTAssertNil(VimInsightsEngine.arrowReliancePercent(
            for: KindaVimTelemetrySnapshot()
        ))
    }

    func testArrowReliancePercentMatchesRatio() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 10, "j": 10]
        snap.nonVimNavigationFrequency = ["left": 5]
        let pct = VimInsightsEngine.arrowReliancePercent(for: snap) ?? 0
        XCTAssertEqual(pct, 20.0, accuracy: 0.001)
    }

    // MARK: - Stage-appropriate rules fire

    func testBeginnerSurfacesArrowShaming() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 10, "j": 10]
        snap.nonVimNavigationFrequency = ["left": 80]
        let insights = VimInsightsEngine.insights(for: snap)
        XCTAssertTrue(insights.contains { $0.glyph == .shame })
    }

    func testIntermediateSurfacesFoundationGapForB() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 30, "j": 30, "w": 20]  // w fluent, b absent
        snap.nonVimNavigationFrequency = ["left": 15]  // ~16% reliance
        let insights = VimInsightsEngine.insights(for: snap)
        XCTAssertTrue(insights.contains { $0.title.contains("`b`") })
    }

    func testAdvancedSurfacesTextObjectsForOperatorUser() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 200, "j": 200, "d": 30, "c": 30]
        snap.nonVimNavigationFrequency = ["left": 20]
        let insights = VimInsightsEngine.insights(for: snap)
        XCTAssertTrue(insights.contains { $0.title.lowercased().contains("text object") })
    }

    func testAdvancedSurfacesParagraphJumpForHeavyJ() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 100, "j": 500, "k": 100, "l": 100]
        snap.nonVimNavigationFrequency = ["left": 10]
        let insights = VimInsightsEngine.insights(for: snap)
        XCTAssertTrue(insights.contains { $0.title.contains("`}`") })
    }

    // MARK: - Caps + ranking

    func testInsightCountIsBounded() {
        // Big snapshot meant to trigger many rules — output should still cap.
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = [
            "h": 200, "j": 500, "k": 100, "l": 100,
            "w": 30, "d": 50, "c": 50, "y": 50,
        ]
        snap.nonVimNavigationFrequency = ["left": 100]
        snap.modeDwellSeconds = ["insert": 5000, "normal": 100]
        snap.strategySamples = ["keyboard": 50, "accessibility": 10]
        let insights = VimInsightsEngine.insights(for: snap, maxInsights: 3)
        XCTAssertLessThanOrEqual(insights.count, 3)
    }

    func testInsightsOrderedByPriority() {
        var snap = KindaVimTelemetrySnapshot()
        snap.commandFrequency = ["h": 30, "j": 30, "i": 30, "w": 30]
        snap.nonVimNavigationFrequency = ["left": 30]  // intermediate
        let insights = VimInsightsEngine.insights(for: snap, maxInsights: 5)
        let priorities = insights.map(\.priority)
        XCTAssertEqual(priorities, priorities.sorted(by: >))
    }

    // MARK: - Onboarding for empty snapshots

    func testEmptySnapshotShowsGetStarted() {
        let insights = VimInsightsEngine.insights(for: KindaVimTelemetrySnapshot())
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights.first?.title, "Get started")
    }
}
