@testable import KeyPathAppKit
import XCTest

final class TimingCopyTests: XCTestCase {
    func testDualRoleVariantsUseApprovedPrimaryTimingLabels() {
        XCTAssertEqual(TimingCopy.DualRoleVariant.basic.primaryWindowLabel, "Repeat-tap window")
        XCTAssertEqual(TimingCopy.DualRoleVariant.holdOnOtherKeyPress.primaryWindowLabel, "Repeat-tap window")
        XCTAssertEqual(TimingCopy.DualRoleVariant.holdOnOtherKeyRelease.primaryWindowLabel, "Repeat-tap window")
        XCTAssertEqual(TimingCopy.DualRoleVariant.customTapKeys.primaryWindowLabel, "Repeat-tap window")
        XCTAssertEqual(TimingCopy.DualRoleVariant.releaseOrder.primaryWindowLabel, "Typing grace period")
    }

    func testOnlySingleClockVariantsHideHoldActivationDelay() {
        XCTAssertTrue(TimingCopy.DualRoleVariant.basic.usesHoldActivationDelay)
        XCTAssertTrue(TimingCopy.DualRoleVariant.holdOnOtherKeyPress.usesHoldActivationDelay)
        XCTAssertTrue(TimingCopy.DualRoleVariant.holdOnOtherKeyRelease.usesHoldActivationDelay)
        XCTAssertTrue(TimingCopy.DualRoleVariant.customTapKeys.usesHoldActivationDelay)
        XCTAssertFalse(TimingCopy.DualRoleVariant.releaseOrder.usesHoldActivationDelay)
        XCTAssertFalse(TimingCopy.DualRoleVariant.oppositeHandPress.usesHoldActivationDelay)
        XCTAssertFalse(TimingCopy.DualRoleVariant.oppositeHandRelease.usesHoldActivationDelay)
    }

    func testEditorStateResolvesToTheSameSharedVariants() {
        XCTAssertEqual(
            TimingCopy.dualRoleVariant(activateHoldOnOtherKey: false, quickTap: false, useReleaseOrder: false),
            .basic
        )
        XCTAssertEqual(
            TimingCopy.dualRoleVariant(activateHoldOnOtherKey: true, quickTap: true, useReleaseOrder: false),
            .holdOnOtherKeyPress
        )
        XCTAssertEqual(
            TimingCopy.dualRoleVariant(for: .quickTap),
            .holdOnOtherKeyRelease
        )
        XCTAssertEqual(TimingCopy.activateHoldOnOtherKeyRelease, "Activate hold after another key is released")
        XCTAssertTrue(TimingCopy.multiTapWindowExplanation.contains("After every tap"))
    }

    func testTapDanceNeverShowsAnUnrelatedHoldActivationDelay() {
        XCTAssertFalse(TimingCopy.showsHoldActivationDelay(for: .basic, isEditingTapDance: true))
        XCTAssertTrue(TimingCopy.showsHoldActivationDelay(for: .basic, isEditingTapDance: false))
    }

    func testLeaderHoldDelayNamesTheKeyAndShortcutListOutcome() {
        XCTAssertEqual(String(localized: TimingCopy.leaderHoldDelay), "Leader hold delay")
        XCTAssertEqual(
            String(localized: TimingCopy.leaderHoldDelayExplanation),
            "How long to hold the Leader key before KeyPath shows the Shortcut List. Default is Long (300 ms). Medium (200 ms) matches previous behavior."
        )
        XCTAssertEqual(
            String(localized: TimingCopy.customLeaderHoldDelayAccessibilityLabel),
            "Custom Leader hold delay in milliseconds"
        )
    }
}
