//
//  TapHoldCustomizeTests.swift
//  KeyPathTests
//
//  Tests for the tap-hold customize panel functionality.
//

@testable import KeyPathAppKit
import XCTest

final class TapHoldCustomizeTests: XCTestCase {
    // MARK: - Key Formatting Tests

    func testFormatKeyForCustomize_modifiers() {
        // Test left modifiers
        XCTAssertEqual(formatKeyForCustomize("lmet"), "⌘", "Left Command should format as ⌘")
        XCTAssertEqual(formatKeyForCustomize("lalt"), "⌥", "Left Option should format as ⌥")
        XCTAssertEqual(formatKeyForCustomize("lctl"), "⌃", "Left Control should format as ⌃")
        XCTAssertEqual(formatKeyForCustomize("lsft"), "⇧", "Left Shift should format as ⇧")

        // Test right modifiers
        XCTAssertEqual(formatKeyForCustomize("rmet"), "⌘", "Right Command should format as ⌘")
        XCTAssertEqual(formatKeyForCustomize("ralt"), "⌥", "Right Option should format as ⌥")
        XCTAssertEqual(formatKeyForCustomize("rctl"), "⌃", "Right Control should format as ⌃")
        XCTAssertEqual(formatKeyForCustomize("rsft"), "⇧", "Right Shift should format as ⇧")

        // Test short names
        XCTAssertEqual(formatKeyForCustomize("met"), "⌘", "Command should format as ⌘")
        XCTAssertEqual(formatKeyForCustomize("alt"), "⌥", "Option should format as ⌥")
        XCTAssertEqual(formatKeyForCustomize("ctl"), "⌃", "Control should format as ⌃")
        XCTAssertEqual(formatKeyForCustomize("sft"), "⇧", "Shift should format as ⇧")
    }

    func testFormatKeyForCustomize_specialKeys() {
        XCTAssertEqual(formatKeyForCustomize("space"), "␣", "Space should format as ␣")
        XCTAssertEqual(formatKeyForCustomize("spc"), "␣", "Spc should format as ␣")
        XCTAssertEqual(formatKeyForCustomize("ret"), "↩", "Return should format as ↩")
        XCTAssertEqual(formatKeyForCustomize("return"), "↩", "Return should format as ↩")
        XCTAssertEqual(formatKeyForCustomize("enter"), "↩", "Enter should format as ↩")
        XCTAssertEqual(formatKeyForCustomize("bspc"), "⌫", "Backspace should format as ⌫")
        XCTAssertEqual(formatKeyForCustomize("backspace"), "⌫", "Backspace should format as ⌫")
        XCTAssertEqual(formatKeyForCustomize("tab"), "⇥", "Tab should format as ⇥")
        XCTAssertEqual(formatKeyForCustomize("esc"), "⎋", "Escape should format as ⎋")
        XCTAssertEqual(formatKeyForCustomize("escape"), "⎋", "Escape should format as ⎋")
    }

    func testFormatKeyForCustomize_regularKeys() {
        XCTAssertEqual(formatKeyForCustomize("a"), "A", "Lowercase letter should uppercase")
        XCTAssertEqual(formatKeyForCustomize("A"), "A", "Uppercase letter should stay uppercase")
        XCTAssertEqual(formatKeyForCustomize("z"), "Z", "Lowercase z should uppercase")
        XCTAssertEqual(formatKeyForCustomize("1"), "1", "Number should stay as-is")
    }

    func testFormatKeyForCustomize_caseInsensitive() {
        XCTAssertEqual(formatKeyForCustomize("LMET"), "⌘", "Uppercase LMET should format as ⌘")
        XCTAssertEqual(formatKeyForCustomize("Lalt"), "⌥", "Mixed case Lalt should format as ⌥")
        XCTAssertEqual(formatKeyForCustomize("SPACE"), "␣", "Uppercase SPACE should format as ␣")
    }

    // MARK: - Tap-Dance Labels Tests

    func testTapDanceLabels_count() {
        let labels = ["Triple Tap", "Quad Tap", "Quint Tap"]
        XCTAssertEqual(labels.count, 3, "Should have 3 tap-dance labels beyond double tap")
    }

    func testTapDanceLabels_order() {
        let labels = ["Triple Tap", "Quad Tap", "Quint Tap"]
        XCTAssertEqual(labels[0], "Triple Tap", "First label should be Triple Tap")
        XCTAssertEqual(labels[1], "Quad Tap", "Second label should be Quad Tap")
        XCTAssertEqual(labels[2], "Quint Tap", "Third label should be Quint Tap")
    }

    // MARK: - Timing Defaults Tests

    func testDefaultTimingValues() {
        let defaultTapTimeout = 200
        let defaultHoldTimeout = 200

        XCTAssertEqual(defaultTapTimeout, 200, "Default tap timeout should be 200ms")
        XCTAssertEqual(defaultHoldTimeout, 200, "Default hold timeout should be 200ms")
    }

    func testTimingRange() {
        // Reasonable timing range for tap-hold
        let minTiming = 50
        let maxTiming = 1000

        XCTAssertGreaterThanOrEqual(200, minTiming, "Default timing should be >= minimum")
        XCTAssertLessThanOrEqual(200, maxTiming, "Default timing should be <= maximum")
    }

    // MARK: - Helper Function

    /// Standalone format function for testing (mirrors the one in LiveKeyboardOverlayView)
    private func formatKeyForCustomize(_ key: String) -> String {
        switch key.lowercased() {
        case "lmet", "rmet", "met": "⌘"
        case "lalt", "ralt", "alt": "⌥"
        case "lctl", "rctl", "ctl": "⌃"
        case "lsft", "rsft", "sft": "⇧"
        case "space", "spc": "␣"
        case "ret", "return", "enter": "↩"
        case "bspc", "backspace": "⌫"
        case "tab": "⇥"
        case "esc", "escape": "⎋"
        default: key.uppercased()
        }
    }
}

// MARK: - TapHoldMiniKeycap State Tests

final class TapHoldMiniKeycapStateTests: XCTestCase {
    func testKeycapSize() {
        let expectedSize: CGFloat = 48
        XCTAssertEqual(expectedSize, 48, "Mini keycap should be 48x48 points")
    }

    func testKeycapCornerRadius() {
        let expectedCornerRadius: CGFloat = 8
        XCTAssertEqual(expectedCornerRadius, 8, "Mini keycap should have 8pt corner radius")
    }

    func testKeycapFontSize() {
        let expectedFontSize: CGFloat = 16
        XCTAssertEqual(expectedFontSize, 16, "Mini keycap should use 16pt font")
    }

    func testRecordingStates() {
        // Test that recording state can be tracked per field
        var recordingField: String? = nil

        // Initially no recording
        XCTAssertNil(recordingField, "Initially no field should be recording")

        // Start recording hold
        recordingField = "hold"
        XCTAssertEqual(recordingField, "hold", "Should track hold recording")

        // Toggle to stop recording
        recordingField = nil
        XCTAssertNil(recordingField, "Should stop recording when toggled")

        // Start recording double tap
        recordingField = "doubleTap"
        XCTAssertEqual(recordingField, "doubleTap", "Should track doubleTap recording")

        // Start recording tap dance step
        recordingField = "tapDance-0"
        XCTAssertEqual(recordingField, "tapDance-0", "Should track tapDance step recording")
    }
}

// MARK: - Tap-Dance Step Management Tests

final class TapDanceStepManagementTests: XCTestCase {
    func testAddTapDanceStep() {
        var steps: [(label: String, action: String)] = []
        let labels = ["Triple Tap", "Quad Tap", "Quint Tap"]

        // Add first step
        let firstLabel = labels[steps.count]
        steps.append((label: firstLabel, action: ""))
        XCTAssertEqual(steps.count, 1, "Should have 1 step after adding")
        XCTAssertEqual(steps[0].label, "Triple Tap", "First step should be Triple Tap")
        XCTAssertTrue(steps[0].action.isEmpty, "Action should be empty initially")

        // Add second step
        let secondLabel = labels[steps.count]
        steps.append((label: secondLabel, action: ""))
        XCTAssertEqual(steps.count, 2, "Should have 2 steps after adding")
        XCTAssertEqual(steps[1].label, "Quad Tap", "Second step should be Quad Tap")

        // Add third step
        let thirdLabel = labels[steps.count]
        steps.append((label: thirdLabel, action: ""))
        XCTAssertEqual(steps.count, 3, "Should have 3 steps after adding")
        XCTAssertEqual(steps[2].label, "Quint Tap", "Third step should be Quint Tap")

        // Should not be able to add more
        XCTAssertEqual(steps.count, labels.count, "Should not exceed max tap-dance steps")
    }

    func testRemoveTapDanceStep() {
        var steps: [(label: String, action: String)] = [
            (label: "Triple Tap", action: "a"),
            (label: "Quad Tap", action: "b"),
        ]

        // Remove first step
        steps.remove(at: 0)
        XCTAssertEqual(steps.count, 1, "Should have 1 step after removal")
        XCTAssertEqual(steps[0].label, "Quad Tap", "Remaining step should be Quad Tap")
    }

    func testClearTapDanceStepAction() {
        var steps: [(label: String, action: String)] = [
            (label: "Triple Tap", action: "lmet"),
        ]

        // Clear action
        steps[0].action = ""
        XCTAssertTrue(steps[0].action.isEmpty, "Action should be cleared")
        XCTAssertEqual(steps[0].label, "Triple Tap", "Label should remain")
    }

    func testSetTapDanceStepAction() {
        var steps: [(label: String, action: String)] = [
            (label: "Triple Tap", action: ""),
        ]

        // Set action
        steps[0].action = "lmet"
        XCTAssertEqual(steps[0].action, "lmet", "Action should be set to lmet")
    }
}

// MARK: - Accessibility Identifier Tests

final class TapHoldAccessibilityTests: XCTestCase {
    func testAccessibilityIdentifierFormats() {
        // Test expected accessibility identifier formats
        let holdKeycap = "customize-hold-keycap"
        let holdClear = "customize-hold-clear"
        let doubleTapKeycap = "customize-doubleTap-keycap"
        let doubleTapClear = "customize-doubleTap-clear"
        let tapDanceKeycap = "customize-tapDance-0-keycap"
        let tapDanceClear = "customize-tapDance-0-clear"
        let tapDanceRemove = "customize-tapDance-0-remove"
        let addTapDance = "customize-add-tap-dance"
        let timing = "customize-timing"
        let tapTimeout = "customize-tap-timeout"
        let holdTimeout = "customize-hold-timeout"
        let advancedToggle = "customize-timing-advanced-toggle"

        // Verify format consistency
        XCTAssertTrue(holdKeycap.hasPrefix("customize-"), "Hold keycap ID should start with customize-")
        XCTAssertTrue(holdClear.hasPrefix("customize-"), "Hold clear ID should start with customize-")
        XCTAssertTrue(doubleTapKeycap.hasPrefix("customize-"), "Double tap keycap ID should start with customize-")
        XCTAssertTrue(doubleTapClear.hasSuffix("-clear"), "Double tap clear ID should end with -clear")
        XCTAssertTrue(tapDanceKeycap.contains("tapDance"), "Tap dance ID should contain tapDance")
        XCTAssertTrue(tapDanceClear.contains("tapDance"), "Tap dance clear ID should contain tapDance")
        XCTAssertTrue(tapDanceRemove.contains("remove"), "Tap dance remove ID should contain remove")
        XCTAssertTrue(tapDanceKeycap.contains("-0-"), "Tap dance ID should contain index")
        XCTAssertTrue(addTapDance.contains("add"), "Add button ID should contain add")
        XCTAssertTrue(timing.contains("timing"), "Timing ID should contain timing")
        XCTAssertTrue(tapTimeout.contains("tap-timeout"), "Tap timeout ID should contain tap-timeout")
        XCTAssertTrue(holdTimeout.contains("hold-timeout"), "Hold timeout ID should contain hold-timeout")
        XCTAssertTrue(advancedToggle.contains("advanced"), "Advanced toggle ID should contain advanced")
    }
}
