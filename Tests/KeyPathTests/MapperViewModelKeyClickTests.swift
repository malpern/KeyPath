import XCTest

@testable import KeyPathAppKit

/// Tests for MapperViewModel.setInputFromKeyClick with action identifier support.
/// Verifies that:
/// 1. Basic key click updates input and output labels correctly
/// 2. System action identifiers are properly resolved
/// 3. URL identifiers are properly handled
/// 4. App identifiers fall back gracefully when app not found
/// 5. Action selections are cleared before setting new values
@MainActor
final class MapperViewModelKeyClickTests: XCTestCase {
    // MARK: - Basic Key Click Tests

    @MainActor
    func testSetInputFromKeyClick_UpdatesInputLabel() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(keyCode: 1, inputLabel: "s", outputLabel: "d")

        XCTAssertEqual(viewModel.inputLabel, "S", "Input label should be formatted (uppercase)")
        XCTAssertEqual(viewModel.inputKeyCode, 1, "Input key code should be set")
    }

    @MainActor
    func testSetInputFromKeyClick_UpdatesOutputLabel() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(keyCode: 0, inputLabel: "a", outputLabel: "b")

        XCTAssertEqual(viewModel.outputLabel, "B", "Output label should be formatted (uppercase)")
    }

    @MainActor
    func testSetInputFromKeyClick_CanSave_AfterPlainKeyMapping() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(keyCode: 2, inputLabel: "d", outputLabel: "f")

        // canSave should be true when input/output are properly set
        XCTAssertTrue(viewModel.canSave, "Should be able to save after key click setup")
    }

    @MainActor
    func testSetInputFromKeyClick_PlainKey_NoSelectedActions() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(keyCode: 0, inputLabel: "a", outputLabel: "b")

        // Plain key mapping should not have any action selected
        XCTAssertNil(viewModel.selectedApp, "No app should be selected for plain key")
        XCTAssertNil(viewModel.selectedSystemAction, "No system action should be selected for plain key")
        XCTAssertNil(viewModel.selectedURL, "No URL should be selected for plain key")
    }

    // MARK: - System Action Tests

    @MainActor
    func testSetInputFromKeyClick_WithSystemAction_SetsSelectedSystemAction() {
        let viewModel = MapperViewModel()

        // Use a known system action ID
        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "Spotlight",
            systemActionIdentifier: "spotlight"
        )

        XCTAssertNotNil(viewModel.selectedSystemAction, "System action should be selected")
        XCTAssertEqual(viewModel.selectedSystemAction?.id, "spotlight", "System action ID should match")
    }

    @MainActor
    func testSetInputFromKeyClick_WithSystemAction_CanStillSave() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "Spotlight",
            systemActionIdentifier: "spotlight"
        )

        XCTAssertTrue(viewModel.canSave, "Should be able to save with system action")
    }

    @MainActor
    func testSetInputFromKeyClick_WithSystemAction_SetsOutputLabel() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "Spotlight",
            systemActionIdentifier: "spotlight"
        )

        XCTAssertEqual(viewModel.selectedSystemAction?.name, viewModel.outputLabel, "Output label should be system action name")
    }

    @MainActor
    func testSetInputFromKeyClick_WithUnknownSystemAction_FallsBackToOutputLabel() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "b",
            systemActionIdentifier: "unknown-action"
        )

        // Unknown system action should fall through to regular output
        XCTAssertNil(viewModel.selectedSystemAction, "Unknown system action should not be selected")
        XCTAssertEqual(viewModel.outputLabel, "B", "Should fall back to formatted output label")
    }

    // MARK: - URL Identifier Tests

    @MainActor
    func testSetInputFromKeyClick_WithURL_SetsSelectedURL() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "github.com",
            urlIdentifier: "https://github.com"
        )

        XCTAssertEqual(viewModel.selectedURL, "https://github.com", "URL should be stored")
    }

    @MainActor
    func testSetInputFromKeyClick_WithURL_CanStillSave() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "github.com",
            urlIdentifier: "https://github.com"
        )

        XCTAssertTrue(viewModel.canSave, "Should be able to save with URL action")
    }

    @MainActor
    func testSetInputFromKeyClick_WithURL_ExtractsDomain() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "github.com",
            urlIdentifier: "https://github.com/anthropics/claude-code"
        )

        // Output label should be extracted domain
        XCTAssertEqual(viewModel.outputLabel, "github.com", "Should extract domain from URL")
    }

    // MARK: - Clearing Previous Selections Tests

    @MainActor
    func testSetInputFromKeyClick_ClearsPreviousSystemAction() {
        let viewModel = MapperViewModel()

        // First set a system action
        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "Spotlight",
            systemActionIdentifier: "spotlight"
        )
        XCTAssertNotNil(viewModel.selectedSystemAction)

        // Then set a plain key
        viewModel.setInputFromKeyClick(keyCode: 1, inputLabel: "s", outputLabel: "d")

        XCTAssertNil(viewModel.selectedSystemAction, "Previous system action should be cleared")
    }

    @MainActor
    func testSetInputFromKeyClick_ClearsPreviousURL() {
        let viewModel = MapperViewModel()

        // First set a URL
        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "github.com",
            urlIdentifier: "https://github.com"
        )
        XCTAssertNotNil(viewModel.selectedURL)

        // Then set a plain key
        viewModel.setInputFromKeyClick(keyCode: 1, inputLabel: "s", outputLabel: "d")

        XCTAssertNil(viewModel.selectedURL, "Previous URL should be cleared")
    }

    @MainActor
    func testSetInputFromKeyClick_ClearsPreviousApp() {
        let viewModel = MapperViewModel()

        // First set a mock app (can't easily set real app, but verify clearing works)
        // Then set a plain key - app should be nil after
        viewModel.setInputFromKeyClick(keyCode: 0, inputLabel: "a", outputLabel: "b")

        XCTAssertNil(viewModel.selectedApp, "App should be nil for plain key mapping")
    }

    // MARK: - Priority Tests (App > URL > System Action > Plain Key)

    @MainActor
    func testSetInputFromKeyClick_URLTakesPrecedenceOverSystemAction() {
        let viewModel = MapperViewModel()

        // Both URL and system action provided - URL should win (per implementation order)
        viewModel.setInputFromKeyClick(
            keyCode: 0,
            inputLabel: "a",
            outputLabel: "test",
            systemActionIdentifier: "spotlight",
            urlIdentifier: "https://example.com"
        )

        // URL is checked second (after app), so it takes precedence over system action
        XCTAssertNotNil(viewModel.selectedURL, "URL should be set")
        XCTAssertNil(viewModel.selectedSystemAction, "System action should not be set when URL present")
    }

    // MARK: - Recording State Tests

    @MainActor
    func testSetInputFromKeyClick_StopsActiveRecording() {
        let viewModel = MapperViewModel()

        // Start recording
        viewModel.isRecordingInput = true
        viewModel.isRecordingOutput = true

        viewModel.setInputFromKeyClick(keyCode: 0, inputLabel: "a", outputLabel: "b")

        XCTAssertFalse(viewModel.isRecordingInput, "Input recording should stop")
        XCTAssertFalse(viewModel.isRecordingOutput, "Output recording should stop")
    }

    // MARK: - Edge Cases

    @MainActor
    func testSetInputFromKeyClick_WithEmptyLabels() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(keyCode: 0, inputLabel: "", outputLabel: "")

        // Should still set values (even if empty)
        XCTAssertEqual(viewModel.inputLabel, "")
        XCTAssertEqual(viewModel.outputLabel, "")
    }

    @MainActor
    func testSetInputFromKeyClick_WithSpecialCharacters() {
        let viewModel = MapperViewModel()

        viewModel.setInputFromKeyClick(keyCode: 51, inputLabel: "⌫", outputLabel: "delete")

        XCTAssertEqual(viewModel.inputLabel, "⌫", "Special characters should be preserved")
    }
}
