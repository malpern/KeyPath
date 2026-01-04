@preconcurrency import XCTest

@testable import KeyPathAppKit

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
}
