import AppKit
@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

/// Tests for MapperViewModel canSave logic, identity mapping detection,
/// shifted output blocking, and conflict state management.
final class MapperConflictAndSaveTests: XCTestCase {
    // MARK: - canSave

    @MainActor
    func testCanSave_DefaultState_IsTrue() {
        let vm = MapperViewModel()
        XCTAssertTrue(vm.canSave, "Default A→A mapping should be saveable")
    }

    @MainActor
    func testCanSave_NilInput_IsFalse() {
        let vm = MapperViewModel()
        vm.inputSequence = nil
        XCTAssertFalse(vm.canSave)
    }

    @MainActor
    func testCanSave_NilOutputButHasApp_IsTrue() {
        let vm = MapperViewModel()
        vm.outputSequence = nil
        vm.selectedApp = AppLaunchInfo(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: NSImage())
        XCTAssertTrue(vm.canSave)
    }

    @MainActor
    func testCanSave_NilOutputButHasSystemAction_IsTrue() {
        let vm = MapperViewModel()
        vm.outputSequence = nil
        vm.selectedSystemAction = SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass")
        XCTAssertTrue(vm.canSave)
    }

    @MainActor
    func testCanSave_NilOutputButHasURL_IsTrue() {
        let vm = MapperViewModel()
        vm.outputSequence = nil
        vm.selectedURL = "https://github.com"
        XCTAssertTrue(vm.canSave)
    }

    @MainActor
    func testCanSave_NilOutputAndNoAction_IsFalse() {
        let vm = MapperViewModel()
        vm.outputSequence = nil
        XCTAssertFalse(vm.canSave)
    }

    // MARK: - isIdentityKeystrokeMapping

    @MainActor
    func testIsIdentityMapping_SameKey_IsTrue() {
        let vm = MapperViewModel()
        // Default is A→A
        XCTAssertTrue(vm.isIdentityKeystrokeMapping)
    }

    @MainActor
    func testIsIdentityMapping_DifferentOutput_IsFalse() {
        let vm = MapperViewModel()
        vm.outputSequence = KeySequence(
            keys: [KeyPress(baseKey: "b", modifiers: [], keyCode: 11)],
            captureMode: .single
        )
        XCTAssertFalse(vm.isIdentityKeystrokeMapping)
    }

    @MainActor
    func testIsIdentityMapping_WithApp_IsFalse() {
        let vm = MapperViewModel()
        vm.selectedApp = AppLaunchInfo(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: NSImage())
        XCTAssertFalse(vm.isIdentityKeystrokeMapping)
    }

    @MainActor
    func testIsIdentityMapping_WithSystemAction_IsFalse() {
        let vm = MapperViewModel()
        vm.selectedSystemAction = SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass")
        XCTAssertFalse(vm.isIdentityKeystrokeMapping)
    }

    @MainActor
    func testIsIdentityMapping_WithAdvancedBehavior_IsFalse() {
        let vm = MapperViewModel()
        vm.holdAction = "lctl"
        XCTAssertFalse(vm.isIdentityKeystrokeMapping, "Hold action makes it non-identity")
    }

    // MARK: - Shifted Output Blocking

    @MainActor
    func testShiftedOutputBlocked_WithAppCondition() {
        let vm = MapperViewModel()
        vm.selectedAppCondition = AppConditionInfo(bundleIdentifier: "com.apple.Safari", displayName: "Safari", icon: NSImage())
        XCTAssertNotNil(vm.shiftedOutputBlockingReason)
        XCTAssertFalse(vm.canUseShiftedOutput)
    }

    @MainActor
    func testShiftedOutputBlocked_WithAppAction() {
        let vm = MapperViewModel()
        vm.selectedApp = AppLaunchInfo(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: NSImage())
        XCTAssertNotNil(vm.shiftedOutputBlockingReason)
        XCTAssertFalse(vm.canUseShiftedOutput)
    }

    @MainActor
    func testShiftedOutputBlocked_WithSystemAction() {
        let vm = MapperViewModel()
        vm.selectedSystemAction = SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass")
        XCTAssertNotNil(vm.shiftedOutputBlockingReason)
        XCTAssertFalse(vm.canUseShiftedOutput)
    }

    @MainActor
    func testShiftedOutputBlocked_WithURL() {
        let vm = MapperViewModel()
        vm.selectedURL = "https://example.com"
        XCTAssertNotNil(vm.shiftedOutputBlockingReason)
        XCTAssertFalse(vm.canUseShiftedOutput)
    }

    @MainActor
    func testShiftedOutputBlocked_WithHoldAction() {
        let vm = MapperViewModel()
        vm.holdAction = "lctl"
        XCTAssertNotNil(vm.shiftedOutputBlockingReason)
        XCTAssertFalse(vm.canUseShiftedOutput)
    }

    @MainActor
    func testShiftedOutputAllowed_PlainKeyMapping() {
        let vm = MapperViewModel()
        XCTAssertNil(vm.shiftedOutputBlockingReason)
        XCTAssertTrue(vm.canUseShiftedOutput)
    }

    // MARK: - Conflict State

    @MainActor
    func testConflictDialog_DefaultsToHidden() {
        let vm = MapperViewModel()
        XCTAssertFalse(vm.showConflictDialog)
        XCTAssertNil(vm.pendingConflictType)
    }

    @MainActor
    func testConflictDialog_HoldVsTapDance() {
        let vm = MapperViewModel()
        vm.pendingConflictType = .holdVsTapDance
        vm.showConflictDialog = true

        XCTAssertTrue(vm.showConflictDialog)
        XCTAssertEqual(vm.pendingConflictType, .holdVsTapDance)
    }

    @MainActor
    func testResolveConflictKeepHold_ClearsTapDance() {
        let vm = MapperViewModel()
        vm.holdAction = "lctl"
        vm.doubleTapAction = "b"
        vm.pendingConflictField = "tapDance"
        vm.pendingConflictType = .holdVsTapDance
        vm.showConflictDialog = true

        vm.resolveConflictKeepHold()

        XCTAssertFalse(vm.showConflictDialog)
        XCTAssertEqual(vm.holdAction, "lctl", "Hold should be preserved")
    }

    @MainActor
    func testResolveConflictKeepTapDance_ClearsHold() {
        let vm = MapperViewModel()
        vm.holdAction = "lctl"
        vm.doubleTapAction = "b"
        vm.pendingConflictField = "hold"
        vm.pendingConflictType = .holdVsTapDance
        vm.showConflictDialog = true

        vm.resolveConflictKeepTapDance()

        XCTAssertFalse(vm.showConflictDialog)
        XCTAssertEqual(vm.holdAction, "", "Hold should be cleared")
    }

    // MARK: - setInputFromKeyClick

    @MainActor
    func testSetInputFromKeyClick_SetsInputLabel() {
        let vm = MapperViewModel()
        vm.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "A",
            outputLabel: "B"
        )
        XCTAssertEqual(vm.inputLabel, "A")
        XCTAssertEqual(vm.outputLabel, "B")
        XCTAssertEqual(vm.inputKeyCode, 0)
    }

    @MainActor
    func testSetInputFromKeyClick_SetsAppIdentifier() {
        let vm = MapperViewModel()
        vm.setInputFromKeyClick(
            keyCode: 1,
            inputLabel: "S",
            outputLabel: "Safari",
            appIdentifier: "com.apple.Safari"
        )
        XCTAssertNotNil(vm.selectedApp)
        XCTAssertEqual(vm.selectedApp?.bundleIdentifier, "com.apple.Safari")
    }

    @MainActor
    func testSetInputFromKeyClick_SetsSystemAction() {
        let vm = MapperViewModel()
        vm.setInputFromKeyClick(
            keyCode: 2,
            inputLabel: "D",
            outputLabel: "Spotlight",
            systemActionIdentifier: "spotlight"
        )
        XCTAssertNotNil(vm.selectedSystemAction)
    }

    @MainActor
    func testSetInputFromKeyClick_SetsURL() {
        let vm = MapperViewModel()
        vm.setInputFromKeyClick(
            keyCode: 5,
            inputLabel: "G",
            outputLabel: "GitHub",
            urlIdentifier: "https://github.com"
        )
        XCTAssertEqual(vm.selectedURL, "https://github.com")
    }

    @MainActor
    func testSetInputFromKeyClick_SetsShiftedOutput() {
        let vm = MapperViewModel()
        vm.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "A",
            outputLabel: "B",
            shiftedOutputKey: "C"
        )
        XCTAssertEqual(vm.shiftedOutputLabel, "C")
    }

    @MainActor
    func testSetInputFromKeyClick_ClearsAppWhenNil() {
        let vm = MapperViewModel()
        vm.selectedApp = AppLaunchInfo(name: "Safari", bundleIdentifier: "com.apple.Safari", icon: NSImage())
        vm.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "A",
            outputLabel: "B"
        )
        XCTAssertNil(vm.selectedApp, "Should clear app when no appIdentifier provided")
    }
}
