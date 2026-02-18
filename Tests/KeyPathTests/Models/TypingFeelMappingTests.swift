@testable import KeyPathAppKit
import XCTest

final class TypingFeelMappingTests: XCTestCase {
    // MARK: - Feel Slider → Values

    func testSliderAtZeroProducesMoreLettersValues() {
        let values = TypingFeelMapping.timingValues(forSliderPosition: 0.0)
        XCTAssertEqual(values.tapWindow, 250, "Position 0.0 should map to max tap window")
        XCTAssertEqual(values.holdDelay, 200, "Position 0.0 should map to max hold delay")
    }

    func testSliderAtOneProducesMoreModifiersValues() {
        let values = TypingFeelMapping.timingValues(forSliderPosition: 1.0)
        XCTAssertEqual(values.tapWindow, 150, "Position 1.0 should map to min tap window")
        XCTAssertEqual(values.holdDelay, 100, "Position 1.0 should map to min hold delay")
    }

    func testSliderAtMidpointProducesDefaultValues() {
        let values = TypingFeelMapping.timingValues(forSliderPosition: 0.5)
        XCTAssertEqual(values.tapWindow, 200, "Position 0.5 should produce default tap window")
        XCTAssertEqual(values.holdDelay, 150, "Position 0.5 should produce default hold delay")
    }

    func testDefaultTimingConfigIsOnCurve() throws {
        let defaults = TimingConfig()
        let position = TypingFeelMapping.sliderPosition(tapWindow: defaults.tapWindow, holdDelay: defaults.holdDelay)
        XCTAssertNotNil(position, "Default timing (200, 150) must be on the curve")
        XCTAssertEqual(try XCTUnwrap(position), 0.5, accuracy: 0.01, "Default timing should map to midpoint")
    }

    func testSliderClampsOutOfRange() {
        let low = TypingFeelMapping.timingValues(forSliderPosition: -0.5)
        XCTAssertEqual(low.tapWindow, 250)
        XCTAssertEqual(low.holdDelay, 200)

        let high = TypingFeelMapping.timingValues(forSliderPosition: 1.5)
        XCTAssertEqual(high.tapWindow, 150)
        XCTAssertEqual(high.holdDelay, 100)
    }

    // MARK: - Values → Slider Position (round-trip)

    func testRoundTripAtBoundaries() {
        for position in stride(from: 0.0, through: 1.0, by: 0.05) {
            let values = TypingFeelMapping.timingValues(forSliderPosition: position)
            let recovered = TypingFeelMapping.sliderPosition(tapWindow: values.tapWindow, holdDelay: values.holdDelay)
            XCTAssertNotNil(recovered, "Round-trip should succeed for position \(position)")
            if let recovered {
                XCTAssertEqual(recovered, position, accuracy: 0.05,
                               "Round-trip should recover position \(position)")
            }
        }
    }

    func testSliderPositionReturnsNilForCustomValues() {
        // tapWindow and holdDelay don't match the linear curve relationship
        let result = TypingFeelMapping.sliderPosition(tapWindow: 175, holdDelay: 120)
        XCTAssertNil(result, "Mismatched values should return nil (Custom)")
    }

    func testSliderPositionReturnsNilForOutOfRangeValues() {
        let result = TypingFeelMapping.sliderPosition(tapWindow: 500, holdDelay: 400)
        XCTAssertNil(result, "Out-of-range values should return nil")
    }

    func testSliderPositionReturnsValueForMatchingValues() throws {
        let position = TypingFeelMapping.sliderPosition(tapWindow: 250, holdDelay: 200)
        XCTAssertNotNil(position)
        XCTAssertEqual(try XCTUnwrap(position), 0.0, accuracy: 0.01)
    }

    // MARK: - Helper Text

    func testHelperTextVariesByPosition() {
        let low = TypingFeelMapping.helperText(forSliderPosition: 0.1)
        let mid = TypingFeelMapping.helperText(forSliderPosition: 0.5)
        let high = TypingFeelMapping.helperText(forSliderPosition: 0.9)

        XCTAssertTrue(low.contains("fast typing"), "Low position should mention fast typing")
        XCTAssertTrue(mid.contains("Balanced"), "Mid position should say balanced")
        XCTAssertTrue(high.contains("quickly"), "High position should mention quick modifiers")
    }

    // MARK: - Finger Group Keys

    func testFingerGroupKeysAreCorrect() {
        XCTAssertEqual(TypingFeelMapping.FingerGroup.pinky.keys.left, "a")
        XCTAssertEqual(TypingFeelMapping.FingerGroup.pinky.keys.right, ";")
        XCTAssertEqual(TypingFeelMapping.FingerGroup.ring.keys.left, "s")
        XCTAssertEqual(TypingFeelMapping.FingerGroup.ring.keys.right, "l")
        XCTAssertEqual(TypingFeelMapping.FingerGroup.middle.keys.left, "d")
        XCTAssertEqual(TypingFeelMapping.FingerGroup.middle.keys.right, "k")
        XCTAssertEqual(TypingFeelMapping.FingerGroup.index.keys.left, "f")
        XCTAssertEqual(TypingFeelMapping.FingerGroup.index.keys.right, "j")
    }

    // MARK: - Per-Finger Sensitivity

    func testFingerSensitivityReadsZeroForDefaults() {
        let timing = TimingConfig()
        for finger in TypingFeelMapping.FingerGroup.allCases {
            let value = TypingFeelMapping.fingerSensitivity(for: finger, in: timing)
            XCTAssertEqual(value, 0, "Default config should have 0 sensitivity for \(finger)")
        }
    }

    func testApplyAndReadBackFingerSensitivity() {
        var timing = TimingConfig()
        TypingFeelMapping.applyFingerSensitivity(40, for: .pinky, to: &timing)

        let readBack = TypingFeelMapping.fingerSensitivity(for: .pinky, in: timing)
        XCTAssertEqual(readBack, 40, "Should read back the applied sensitivity")

        // Verify both keys and both offset types are set
        XCTAssertEqual(timing.tapOffsets["a"], 40)
        XCTAssertEqual(timing.tapOffsets[";"], 40)
        XCTAssertEqual(timing.holdOffsets["a"], 40)
        XCTAssertEqual(timing.holdOffsets[";"], 40)
    }

    func testApplyZeroRemovesOffsets() {
        var timing = TimingConfig()
        TypingFeelMapping.applyFingerSensitivity(40, for: .pinky, to: &timing)
        TypingFeelMapping.applyFingerSensitivity(0, for: .pinky, to: &timing)

        XCTAssertNil(timing.tapOffsets["a"])
        XCTAssertNil(timing.tapOffsets[";"])
        XCTAssertNil(timing.holdOffsets["a"])
        XCTAssertNil(timing.holdOffsets[";"])
    }

    func testFingerSensitivityClampsToRange() {
        var timing = TimingConfig()
        TypingFeelMapping.applyFingerSensitivity(100, for: .index, to: &timing)
        XCTAssertEqual(timing.tapOffsets["f"], 80, "Should clamp to max 80ms")

        TypingFeelMapping.applyFingerSensitivity(-10, for: .index, to: &timing)
        XCTAssertNil(timing.tapOffsets["f"], "Negative should clamp to 0 and remove")
    }

    func testFingerSensitivityReturnsNilForInconsistentOffsets() {
        var timing = TimingConfig()
        // Set tap offset for left key only
        timing.tapOffsets["a"] = 30
        // Leave hold offset and right key at 0

        let result = TypingFeelMapping.fingerSensitivity(for: .pinky, in: timing)
        XCTAssertNil(result, "Inconsistent offsets should return nil")
    }

    // MARK: - Snap to Curve

    func testSnapToCurveReturnsIdenticalForOnCurveValues() {
        let snapped = TypingFeelMapping.snapToCurve(tapWindow: 200, holdDelay: 150)
        XCTAssertEqual(snapped.tapWindow, 200, "On-curve values should not change")
        XCTAssertEqual(snapped.holdDelay, 150, "On-curve values should not change")
    }

    func testSnapToCurveSnapsOffCurveValues() {
        // 175, 120 is off-curve (tap suggests 0.75, hold suggests 0.80 → avg ~0.775 → snaps to 0.80)
        let snapped = TypingFeelMapping.snapToCurve(tapWindow: 175, holdDelay: 120)
        // Should produce valid on-curve values
        let recovered = TypingFeelMapping.sliderPosition(tapWindow: snapped.tapWindow, holdDelay: snapped.holdDelay)
        XCTAssertNotNil(recovered, "Snapped values must lie on the curve")
    }

    func testSnapToCurveHandlesOutOfRange() {
        let snapped = TypingFeelMapping.snapToCurve(tapWindow: 500, holdDelay: 400)
        // Should clamp to the "More Letters" end
        XCTAssertEqual(snapped.tapWindow, 250)
        XCTAssertEqual(snapped.holdDelay, 200)
    }

    func testMultipleFingersIndependent() {
        var timing = TimingConfig()
        TypingFeelMapping.applyFingerSensitivity(40, for: .pinky, to: &timing)
        TypingFeelMapping.applyFingerSensitivity(10, for: .ring, to: &timing)

        XCTAssertEqual(TypingFeelMapping.fingerSensitivity(for: .pinky, in: timing), 40)
        XCTAssertEqual(TypingFeelMapping.fingerSensitivity(for: .ring, in: timing), 10)
        XCTAssertEqual(TypingFeelMapping.fingerSensitivity(for: .middle, in: timing), 0)
        XCTAssertEqual(TypingFeelMapping.fingerSensitivity(for: .index, in: timing), 0)
    }
}
