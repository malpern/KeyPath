import Foundation
import KeyPathRulesCore
@preconcurrency import XCTest

final class KeyRepeatSpeedScaleTests: XCTestCase {
    func testMovingTowardHigherRatesAlwaysReducesInterval() {
        let scale = KeyRepeatControlConfig.globalSpeedScale

        XCTAssertGreaterThan(
            scale.repeatsPerSecond(forIntervalMs: 20),
            scale.repeatsPerSecond(forIntervalMs: 30)
        )
        XCTAssertLessThan(
            scale.intervalMs(forRepeatsPerSecond: 50),
            scale.intervalMs(forRepeatsPerSecond: 25)
        )
    }

    func testSupportedIntervalsRoundTripExactly() {
        for scale in [
            KeyRepeatControlConfig.globalSpeedScale,
            KeyRepeatControlConfig.overrideSpeedScale,
        ] {
            for interval in stride(
                from: scale.intervalRange.lowerBound,
                through: scale.intervalRange.upperBound,
                by: scale.intervalStep
            ) {
                let repeatsPerSecond = scale.repeatsPerSecond(forIntervalMs: interval)
                XCTAssertEqual(
                    scale.intervalMs(forRepeatsPerSecond: repeatsPerSecond),
                    interval,
                    "Expected \(interval) ms to round-trip"
                )
            }
        }
    }

    func testArbitraryRatesRoundToNearestSupportedInterval() {
        let scale = KeyRepeatControlConfig.globalSpeedScale

        XCTAssertEqual(scale.intervalMs(forRepeatsPerSecond: 58), 15)
        XCTAssertEqual(scale.intervalMs(forRepeatsPerSecond: 45), 20)
        XCTAssertEqual(scale.intervalMs(forRepeatsPerSecond: 40), 25)
    }

    func testRatesClampToSupportedRange() {
        let scale = KeyRepeatControlConfig.globalSpeedScale

        XCTAssertEqual(scale.intervalMs(forRepeatsPerSecond: 1), 200)
        XCTAssertEqual(scale.intervalMs(forRepeatsPerSecond: 1000), 5)
        XCTAssertEqual(scale.intervalMs(forRepeatsPerSecond: 0), 200)
        XCTAssertEqual(scale.intervalMs(forRepeatsPerSecond: .nan), 200)
        XCTAssertEqual(scale.intervalMs(forRepeatsPerSecond: .infinity), 5)
    }

    func testConfigurationPersistsConvertedIntervalWithoutUnitDrift() throws {
        let interval = KeyRepeatControlConfig.globalSpeedScale.intervalMs(forRepeatsPerSecond: 50)
        let original = KeyRepeatControlConfig(
            globalDelayMs: 450,
            globalIntervalMs: interval,
            perKeyOverrides: [
                KeyRepeatOverride(key: "left", delayMs: 120, intervalMs: interval),
            ]
        )

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(KeyRepeatControlConfig.self, from: data)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.globalIntervalMs, 20)
        XCTAssertEqual(restored.perKeyOverrides.first?.intervalMs, 20)
    }
}
