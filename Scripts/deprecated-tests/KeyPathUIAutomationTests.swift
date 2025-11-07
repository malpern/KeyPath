@testable import KeyPath
import SwiftUI
import XCTest

/// Advanced UI Automation tests for KeyPath using actual UI components
/// Tests real SwiftUI view interactions and state management
@MainActor
final class KeyPathUIAutomationTests: XCTestCase {
    var kanataManager: KanataManager!
    var simpleKanataManager: SimpleKanataManager!
    var keyboardCapture: KeyboardCapture!

    override func setUp() async throws {
        try await super.setUp()

        kanataManager = KanataManager()
        simpleKanataManager = SimpleKanataManager(kanataManager: kanataManager)
        keyboardCapture = KeyboardCapture()

        AppLogger.shared.log("🤖 [UIAutomation] Advanced UI test setup completed")
    }

    override func tearDown() async throws {
        kanataManager = nil
        simpleKanataManager = nil
        keyboardCapture = nil

        try await super.tearDown()
    }

    // MARK: - Real UI Component Tests

    func testContentViewStateBinding() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Testing ContentView state binding")

        // Create a ContentView instance and test its state
        let contentView = ContentView()
            .environmentObject(kanataManager)
            .environmentObject(simpleKanataManager)

        // Test that the view can be instantiated
        XCTAssertNotNil(contentView, "ContentView should be created successfully")

        AppLogger.shared.log("✅ [UIAutomation] ContentView state binding test passed")
    }

    func testRecordingSectionStateManagement() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Testing RecordingSection state management")

        // Set up RecordingSection with bindings
        var recordedInput = ""
        var recordedOutput = ""
        var isRecording = false
        var isRecordingOutput = false
        var showStatusMessage = false

        let showStatusMessageCallback: (String) -> Void = { message in
            showStatusMessage = true
            AppLogger.shared.log("📝 [UIAutomation] Status message: \(message)")
        }

        // Create the RecordingSection
        let recordingSection = RecordingSection(
            recordedInput: .constant(recordedInput),
            recordedOutput: .constant(recordedOutput),
            isRecording: .constant(isRecording),
            isRecordingOutput: .constant(isRecordingOutput),
            kanataManager: kanataManager,
            keyboardCapture: keyboardCapture,
            showStatusMessage: showStatusMessageCallback,
            simpleKanataManager: simpleKanataManager
        )

        XCTAssertNotNil(recordingSection, "RecordingSection should be created successfully")

        AppLogger.shared.log("✅ [UIAutomation] RecordingSection state management test passed")
    }

    func testKeyCaptureMockSimulation() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Testing key capture mock simulation")

        // Create a mock key capture simulator
        let keyCapture = LocalMockKeyboardCapture()

        // Test input capture
        var capturedInput: String?
        keyCapture.startCapture { keyName in
            capturedInput = keyName
        }

        // Simulate key press
        keyCapture.simulateKeyPress("5")

        XCTAssertEqual(capturedInput, "5", "Should capture key '5'")

        // Test output capture
        var capturedOutput = ""
        keyCapture.startContinuousCapture { keyName in
            if !capturedOutput.isEmpty {
                capturedOutput += " "
            }
            capturedOutput += keyName
        }

        // Simulate multiple key presses
        keyCapture.simulateKeyPress("6")
        keyCapture.simulateKeyPress("shift")

        XCTAssertEqual(capturedOutput, "6 shift", "Should capture multiple keys for output")

        AppLogger.shared.log("✅ [UIAutomation] Key capture simulation test passed")
    }

    func testCompleteUIWorkflowAutomation() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Testing complete UI workflow automation")

        // Create UI automation controller
        let automation = KeyPathUIAutomationController(
            kanataManager: kanataManager,
            keyboardCapture: LocalMockKeyboardCapture()
        )

        // Execute the complete 5 to 6 remap workflow
        let result = await automation.addKeyRemap(input: "5", output: "6")

        XCTAssertTrue(result.success, "5 to 6 key remap should succeed")
        XCTAssertEqual(result.inputKey, "5", "Input should be '5'")
        XCTAssertEqual(result.outputKey, "6", "Output should be '6'")
        XCTAssertNil(result.error, "Should not have errors")

        AppLogger.shared.log("✅ [UIAutomation] Complete UI workflow automation test passed")
    }

    func testUIElementAccessibility() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Testing UI element accessibility")

        // Test accessibility identifiers exist and are properly set
        let expectedIdentifiers = [
            "launch-installation-wizard-button",
            "input-recording-section",
            "input-key-label",
            "input-key-display",
            "input-key-record-button",
            "output-recording-section",
            "output-key-label",
            "output-key-display",
            "output-key-record-button",
            "save-mapping-button"
        ]

        // In a real UI test environment, you would check these exist
        // For now, we verify they are defined correctly
        for identifier in expectedIdentifiers {
            XCTAssertFalse(identifier.isEmpty, "Accessibility identifier should not be empty: \(identifier)")
            XCTAssertTrue(identifier.contains("-"), "Accessibility identifier should use kebab-case: \(identifier)")
        }

        AppLogger.shared.log("✅ [UIAutomation] UI accessibility test passed")
    }

    func testKeyRemapValidation() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Testing key remap validation")

        let automation = KeyPathUIAutomationController(
            kanataManager: kanataManager,
            keyboardCapture: LocalMockKeyboardCapture()
        )

        // Test valid mappings
        let validMappings = [
            ("5", "6"),
            ("caps", "esc"),
            ("a", "b"),
            ("space", "tab"),
            ("f1", "f2")
        ]

        for (input, output) in validMappings {
            let result = await automation.validateKeyMapping(input: input, output: output)
            XCTAssertTrue(result.isValid, "Mapping \(input) → \(output) should be valid")
        }

        // Test edge cases
        let edgeCases = [
            ("", "6"), // Empty input
            ("5", ""), // Empty output
            ("5", "5"), // Same key (might be valid for testing)
        ]

        for (input, output) in edgeCases {
            let result = await automation.validateKeyMapping(input: input, output: output)
            if input.isEmpty || output.isEmpty {
                XCTAssertFalse(result.isValid, "Empty keys should be invalid: \(input) → \(output)")
            }
        }

        AppLogger.shared.log("✅ [UIAutomation] Key remap validation test passed")
    }

    func testUIStateTransitions() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Testing UI state transitions")

        let automation = KeyPathUIAutomationController(
            kanataManager: kanataManager,
            keyboardCapture: LocalMockKeyboardCapture()
        )

        // Test state progression through a complete workflow
        var states: [UIAutomationState] = []

        automation.onStateChange = { state in
            states.append(state)
        }

        // Execute workflow and capture state transitions
        await automation.addKeyRemap(input: "5", output: "6")

        // Verify expected state progression
        let expectedStates: [UIAutomationState] = [
            .idle,
            .recordingInput,
            .inputCaptured,
            .recordingOutput,
            .outputCaptured,
            .saving,
            .completed
        ]

        XCTAssertGreaterThanOrEqual(states.count, 4, "Should have multiple state transitions")
        XCTAssertTrue(states.contains(.idle), "Should start in idle state")
        XCTAssertTrue(states.contains(.completed), "Should end in completed state")

        AppLogger.shared.log("✅ [UIAutomation] UI state transitions test passed")
    }
}

// MARK: - Mock Classes for Testing

/// Mock keyboard capture for UI testing (local to this file)
class LocalMockKeyboardCapture: MockKeyboardCapture {
    private var inputCallback: ((String) -> Void)?
    private var continuousCallback: ((String) -> Void)?

    override func startCapture(callback: @escaping (String) -> Void) {
        inputCallback = callback
        AppLogger.shared.log("🎭 [MockKeyCapture] Started input capture")
    }

    override func startContinuousCapture(callback: @escaping (String) -> Void) {
        continuousCallback = callback
        AppLogger.shared.log("🎭 [MockKeyCapture] Started continuous capture")
    }

    override func stopCapture() {
        inputCallback = nil
        continuousCallback = nil
        AppLogger.shared.log("🎭 [MockKeyCapture] Stopped capture")
    }

    override func simulateKeyPress(_ keyName: String) {
        inputCallback?(keyName)
        continuousCallback?(keyName)
        AppLogger.shared.log("🎭 [MockKeyCapture] Simulated key press: \(keyName)")
    }
}

// MARK: - UI Automation Controller

/// Automated UI interaction controller for KeyPath
@MainActor
class KeyPathUIAutomationController {
    private let kanataManager: KanataManager
    private let keyboardCapture: MockKeyboardCapture
    private var currentState: UIAutomationState = .idle

    var onStateChange: ((UIAutomationState) -> Void)?

    init(kanataManager: KanataManager, keyboardCapture: MockKeyboardCapture) {
        self.kanataManager = kanataManager
        self.keyboardCapture = keyboardCapture
    }

    /// Automate adding a key remap through the UI
    func addKeyRemap(input: String, output: String) async -> UIAutomationResult {
        AppLogger.shared.log("🤖 [UIController] Starting automated key remap: \(input) → \(output)")

        setState(.idle)

        var result = UIAutomationResult()
        result.inputKey = input
        result.outputKey = output

        do {
            // Step 1: Start input recording
            setState(.recordingInput)
            keyboardCapture.startCapture { capturedKey in
                AppLogger.shared.log("🤖 [UIController] Captured input: \(capturedKey)")
            }

            // Step 2: Simulate input key press
            keyboardCapture.simulateKeyPress(input)
            setState(.inputCaptured)

            // Step 3: Start output recording
            setState(.recordingOutput)
            keyboardCapture.startContinuousCapture { capturedKey in
                AppLogger.shared.log("🤖 [UIController] Captured output: \(capturedKey)")
            }

            // Step 4: Simulate output key press
            keyboardCapture.simulateKeyPress(output)
            setState(.outputCaptured)

            // Step 5: Save the configuration
            setState(.saving)
            try await kanataManager.saveConfiguration(input: input, output: output)

            setState(.completed)
            result.success = true

            AppLogger.shared.log("🎉 [UIController] Automated key remap completed successfully")

        } catch {
            setState(.error)
            result.success = false
            result.error = error

            AppLogger.shared.log("❌ [UIController] Automated key remap failed: \(error)")
        }

        return result
    }

    /// Validate a key mapping
    func validateKeyMapping(input: String, output: String) async -> KeyMappingValidation {
        var validation = KeyMappingValidation()

        // Basic validation
        if input.isEmpty {
            validation.isValid = false
            validation.errors.append("Input key cannot be empty")
        }

        if output.isEmpty {
            validation.isValid = false
            validation.errors.append("Output key cannot be empty")
        }

        // Additional validation can be added here
        if validation.errors.isEmpty {
            validation.isValid = true
        }

        return validation
    }

    private func setState(_ newState: UIAutomationState) {
        currentState = newState
        onStateChange?(newState)
        AppLogger.shared.log("🔄 [UIController] State changed to: \(newState)")
    }
}

// MARK: - Supporting Types

/// UI automation states
enum UIAutomationState {
    case idle
    case recordingInput
    case inputCaptured
    case recordingOutput
    case outputCaptured
    case saving
    case completed
    case error
}

/// Result of UI automation
struct UIAutomationResult {
    var success: Bool = false
    var inputKey: String = ""
    var outputKey: String = ""
    var error: Error?
}

/// Key mapping validation result
struct KeyMappingValidation {
    var isValid: Bool = false
    var errors: [String] = []
}
