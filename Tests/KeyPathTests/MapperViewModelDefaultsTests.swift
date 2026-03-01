import AppKit
@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Tests for MapperViewModel's default values and identity mapping behavior.
/// Verifies that:
/// 1. Default A→A values exist so output-only changes work
/// 2. canSave reflects the state correctly
final class MapperViewModelDefaultsTests: XCTestCase {
    // MARK: - Default Label Tests

    @MainActor
    func testDefaultInputLabel_IsA() {
        let viewModel = MapperViewModel()

        // Default should be A key
        XCTAssertEqual(viewModel.inputLabel, "A")
    }

    @MainActor
    func testDefaultOutputLabel_IsA() {
        let viewModel = MapperViewModel()

        // Default should be A key
        XCTAssertEqual(viewModel.outputLabel, "A")
    }

    @MainActor
    func testDefaultInputKeyCode_IsZero() {
        let viewModel = MapperViewModel()

        // Default keyCode for A is 0
        XCTAssertEqual(viewModel.inputKeyCode, 0)
    }

    // MARK: - canSave Tests

    @MainActor
    func testCanSave_DefaultState_IsTrue() {
        let viewModel = MapperViewModel()

        // With default sequences initialized, canSave should be true
        // (though identity mapping will be rejected at save time)
        XCTAssertTrue(viewModel.canSave)
    }

    @MainActor
    func testCanSave_AfterOutputChange_IsTrue() {
        let viewModel = MapperViewModel()

        // Simulate user changing only the output label
        viewModel.outputLabel = "B"

        // canSave should still be true since input exists by default
        XCTAssertTrue(viewModel.canSave)
    }

    // MARK: - State After Initialization

    @MainActor
    func testInitialState_HasNoStatusMessage() {
        let viewModel = MapperViewModel()

        XCTAssertNil(viewModel.statusMessage)
    }

    @MainActor
    func testInitialState_IsNotSaving() {
        let viewModel = MapperViewModel()

        XCTAssertFalse(viewModel.isSaving)
    }

    @MainActor
    func testInitialState_HasNoSelectedApp() {
        let viewModel = MapperViewModel()

        XCTAssertNil(viewModel.selectedApp)
    }

    @MainActor
    func testInitialState_HasNoSelectedSystemAction() {
        let viewModel = MapperViewModel()

        XCTAssertNil(viewModel.selectedSystemAction)
    }

    @MainActor
    func testInitialState_HasNoSelectedAppCondition() {
        let viewModel = MapperViewModel()

        XCTAssertNil(viewModel.selectedAppCondition)
    }

    // MARK: - Shifted Output Availability

    @MainActor
    func testShiftedOutput_DefaultState_IsAvailableAndUnset() {
        let viewModel = MapperViewModel()

        XCTAssertFalse(viewModel.hasShiftedOutputConfigured)
        XCTAssertTrue(viewModel.canUseShiftedOutput)
        XCTAssertNil(viewModel.shiftedOutputBlockingReason)
    }

    @MainActor
    func testShiftedOutput_BlockedWhenAppConditionSelected() {
        let viewModel = MapperViewModel()
        viewModel.selectedAppCondition = AppConditionInfo(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            icon: NSImage(size: NSSize(width: 16, height: 16))
        )

        XCTAssertFalse(viewModel.canUseShiftedOutput)
        XCTAssertEqual(viewModel.shiftedOutputBlockingReason, "Shift output is only available for rules that apply everywhere.")
    }

    @MainActor
    func testShiftedOutput_BlockedWhenSystemActionSelected() {
        let viewModel = MapperViewModel()
        viewModel.selectedSystemAction = SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass")

        XCTAssertFalse(viewModel.canUseShiftedOutput)
        XCTAssertEqual(viewModel.shiftedOutputBlockingReason, "Shift output works only with keystroke output.")
    }

    @MainActor
    func testSelectedAppCondition_ClearsShiftedOutput() {
        let viewModel = MapperViewModel()
        viewModel.applyShiftedOutputPreset("M-down")
        XCTAssertTrue(viewModel.hasShiftedOutputConfigured)

        viewModel.selectedAppCondition = AppConditionInfo(
            bundleIdentifier: "com.apple.Bear",
            displayName: "Bear",
            icon: NSImage(size: NSSize(width: 16, height: 16))
        )

        XCTAssertFalse(viewModel.hasShiftedOutputConfigured)
        XCTAssertNil(viewModel.shiftedOutputLabel)
    }

    @MainActor
    func testIdentityKeystrokeMapping_UsesCanonicalSequencesNotLabels() {
        let viewModel = MapperViewModel()

        viewModel.inputSequence = KeySequence(
            keys: [KeyPress(baseKey: "escape", modifiers: [], keyCode: 53)],
            captureMode: .single
        )
        viewModel.outputSequence = KeySequence(
            keys: [KeyPress(baseKey: "escape", modifiers: [], keyCode: 53)],
            captureMode: .single
        )

        viewModel.inputLabel = "Different UI Label A"
        viewModel.outputLabel = "Different UI Label B"

        XCTAssertTrue(viewModel.isIdentityKeystrokeMapping)
    }

    @MainActor
    func testIdentityKeystrokeMapping_FalseWhenOutputDiffers() {
        let viewModel = MapperViewModel()

        viewModel.inputSequence = KeySequence(
            keys: [KeyPress(baseKey: "a", modifiers: [], keyCode: 0)],
            captureMode: .single
        )
        viewModel.outputSequence = KeySequence(
            keys: [KeyPress(baseKey: "b", modifiers: [], keyCode: 11)],
            captureMode: .single
        )

        XCTAssertFalse(viewModel.isIdentityKeystrokeMapping)
    }
}
