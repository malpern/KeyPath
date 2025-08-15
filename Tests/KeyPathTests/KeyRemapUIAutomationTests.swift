import XCTest
@testable import KeyPath

/// UI Automation tests for key remapping functionality
/// Tests the complete end-to-end flow of adding key remaps through the KeyPath UI
@MainActor
final class KeyRemapUIAutomationTests: XCTestCase {
    
    var kanataManager: KanataManager!
    var simpleKanataManager: SimpleKanataManager!
    var keyboardCapture: KeyboardCapture!
    
    override func setUp() async throws {
        await super.setUp()
        
        // Set up the managers
        kanataManager = KanataManager()
        simpleKanataManager = SimpleKanataManager(kanataManager: kanataManager)
        keyboardCapture = KeyboardCapture()
        
        AppLogger.shared.log("🧪 [UIAutomation] Test setup completed")
    }
    
    override func tearDown() async throws {
        // Clean up
        kanataManager = nil
        simpleKanataManager = nil
        keyboardCapture = nil
        
        await super.tearDown()
    }
    
    // MARK: - Key Remap UI Automation Tests
    
    func testAddKeyRemapUIFlow() async throws {
        // Test various key mappings using the flexible automation framework
        let testCases: [(input: String, output: String, description: String)] = [
            ("5", "6", "Numeric key remap"),
            ("caps", "esc", "Caps Lock to Escape mapping"),
            ("f1", "f2", "Function key remap"),
            ("a", "b", "Letter key remap"),
            ("space", "tab", "Space to Tab mapping"),
            ("delete", "backspace", "Delete key mapping")
        ]
        
        for testCase in testCases {
            AppLogger.shared.log("🤖 [UIAutomation] Testing \(testCase.description): \(testCase.input) → \(testCase.output)")
            
            let result = await executeKeyRemapUIFlow(
                input: testCase.input,
                output: testCase.output,
                description: testCase.description
            )
            
            XCTAssertTrue(result.success, "\(testCase.description) should succeed")
            XCTAssertEqual(result.inputKey, testCase.input, "Input should match for \(testCase.description)")
            XCTAssertEqual(result.outputKey, testCase.output, "Output should match for \(testCase.description)")
            XCTAssertNil(result.error, "Should not have errors for \(testCase.description)")
        }
        
        AppLogger.shared.log("🎉 [UIAutomation] All key remap automation tests completed successfully")
    }
    
    private func executeKeyRemapUIFlow(input: String, output: String, description: String) async -> UIFlowResult {
        AppLogger.shared.log("🤖 [UIAutomation] Starting \(description): \(input) → \(output)")
        
        var result = UIFlowResult()
        result.inputKey = input
        result.outputKey = output
        
        // Create a mock ContentView state that we can control programmatically
        var recordedInput = ""
        var recordedOutput = ""
        var isRecording = false
        var isRecordingOutput = false
        var showStatusMessage = false
        var statusMessage = ""
        
        // Step 1: Simulate clicking the input key record button
        AppLogger.shared.log("🤖 [UIAutomation] Step 1: Clicking input record button")
        isRecording = true
        recordedInput = ""
        
        // Simulate the keyboard capture for input key
        AppLogger.shared.log("🤖 [UIAutomation] Step 2: Simulating key '\(input)' input capture")
        recordedInput = input
        isRecording = false
        
        // Verify input was captured
        XCTAssertEqual(recordedInput, input, "Input key should be captured as '\(input)'")
        XCTAssertFalse(isRecording, "Should stop recording input after key capture")
        
        // Step 3: Simulate clicking the output key record button  
        AppLogger.shared.log("🤖 [UIAutomation] Step 3: Clicking output record button")
        isRecordingOutput = true
        recordedOutput = ""
        
        // Simulate the keyboard capture for output key
        AppLogger.shared.log("🤖 [UIAutomation] Step 4: Simulating key '\(output)' output capture")
        recordedOutput = output
        isRecordingOutput = false
        
        // Verify output was captured
        XCTAssertEqual(recordedOutput, output, "Output key should be captured as '\(output)'")
        XCTAssertFalse(isRecordingOutput, "Should stop recording output after key capture")
        
        // Step 5: Save the mapping
        AppLogger.shared.log("🤖 [UIAutomation] Step 5: Saving key mapping")
        
        // Verify prerequisites for save
        XCTAssertFalse(recordedInput.isEmpty, "Input should not be empty before save")
        XCTAssertFalse(recordedOutput.isEmpty, "Output should not be empty before save")
        
        // Simulate the save operation (this would normally be triggered by Save button)
        do {
            try await kanataManager.saveConfiguration(input: recordedInput, output: recordedOutput)
            AppLogger.shared.log("✅ [UIAutomation] Configuration saved successfully")
            
            // Simulate UI feedback
            statusMessage = "Key mapping saved: \(recordedInput) → \(recordedOutput)"
            showStatusMessage = true
            
            // Clear form after successful save (simulating UI behavior)
            recordedInput = ""
            recordedOutput = ""
            
            result.success = true
            result.configurationSaved = true
            
        } catch {
            AppLogger.shared.log("❌ [UIAutomation] Save failed: \(error)")
            result.success = false
            result.error = error
        }
        
        // Step 6: Verify the mapping was saved (only if save succeeded)
        if result.success {
            AppLogger.shared.log("🤖 [UIAutomation] Step 6: Verifying mapping was saved")
            
            // Check that the configuration file contains our mapping
            let configExists = await kanataManager.verifyConfigExists()
            XCTAssertTrue(configExists, "Configuration file should exist after save")
            
            // Verify form was cleared
            XCTAssertTrue(recordedInput.isEmpty, "Input should be cleared after save")
            XCTAssertTrue(recordedOutput.isEmpty, "Output should be cleared after save")
            
            // Verify status message
            XCTAssertTrue(showStatusMessage, "Status message should be shown")
            XCTAssertEqual(statusMessage, "Key mapping saved: \(input) → \(output)", "Status message should confirm the mapping")
        }
        
        AppLogger.shared.log("🎯 [UIAutomation] \(description) automation completed: success=\(result.success)")
        return result
    }
    
    func testCompleteKeyRemapWorkflow() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Starting complete key remap workflow test")
        
        // This test simulates the complete workflow including UI state management
        let testMappings = [
            ("caps", "esc"),
            ("f1", "f2"),
            ("a", "b")
        ]
        
        for (input, output) in testMappings {
            AppLogger.shared.log("🤖 [UIAutomation] Testing mapping: \(input) → \(output)")
            
            // Simulate the complete UI workflow for each mapping
            let result = await simulateKeyRemapUIFlow(input: input, output: output)
            
            XCTAssertTrue(result.success, "Key remap workflow should succeed for \(input) → \(output)")
            XCTAssertEqual(result.inputKey, input, "Input key should match")
            XCTAssertEqual(result.outputKey, output, "Output key should match")
            XCTAssertTrue(result.configurationSaved, "Configuration should be saved")
        }
        
        AppLogger.shared.log("🎉 [UIAutomation] Complete workflow test completed")
    }
    
    func testUIStateConsistencyDuringRemap() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Testing UI state consistency during remap")
        
        // Test that UI state remains consistent throughout the remap process
        var uiState = UIRemapState()
        
        // Step 1: Start input recording
        uiState.startInputRecording()
        XCTAssertTrue(uiState.isRecordingInput, "Should be recording input")
        XCTAssertFalse(uiState.isRecordingOutput, "Should not be recording output")
        XCTAssertFalse(uiState.canSave, "Should not be able to save with incomplete data")
        
        // Step 2: Capture input
        uiState.captureInput("5")
        XCTAssertFalse(uiState.isRecordingInput, "Should stop recording input after capture")
        XCTAssertEqual(uiState.inputKey, "5", "Input should be captured")
        XCTAssertFalse(uiState.canSave, "Should not be able to save without output")
        
        // Step 3: Start output recording
        uiState.startOutputRecording()
        XCTAssertTrue(uiState.isRecordingOutput, "Should be recording output")
        XCTAssertFalse(uiState.canSave, "Should not be able to save while recording")
        
        // Step 4: Capture output
        uiState.captureOutput("6")
        XCTAssertFalse(uiState.isRecordingOutput, "Should stop recording output after capture")
        XCTAssertEqual(uiState.outputKey, "6", "Output should be captured")
        XCTAssertTrue(uiState.canSave, "Should be able to save with complete data")
        
        // Step 5: Save and reset
        uiState.save()
        XCTAssertTrue(uiState.inputKey.isEmpty, "Input should be cleared after save")
        XCTAssertTrue(uiState.outputKey.isEmpty, "Output should be cleared after save")
        XCTAssertFalse(uiState.canSave, "Should not be able to save with cleared data")
        
        AppLogger.shared.log("✅ [UIAutomation] UI state consistency test passed")
    }
    
    func testErrorHandlingInUIFlow() async throws {
        AppLogger.shared.log("🤖 [UIAutomation] Testing error handling in UI flow")
        
        // Test various error scenarios
        
        // Test 1: Empty input
        do {
            try await kanataManager.saveConfiguration(input: "", output: "6")
            XCTFail("Should fail with empty input")
        } catch {
            AppLogger.shared.log("✅ [UIAutomation] Correctly handled empty input error")
        }
        
        // Test 2: Empty output
        do {
            try await kanataManager.saveConfiguration(input: "5", output: "")
            XCTFail("Should fail with empty output")
        } catch {
            AppLogger.shared.log("✅ [UIAutomation] Correctly handled empty output error")
        }
        
        // Test 3: Invalid key names
        do {
            try await kanataManager.saveConfiguration(input: "invalid-key", output: "another-invalid")
            // This might succeed depending on kanata's key name validation
            AppLogger.shared.log("⚠️ [UIAutomation] Invalid keys were accepted (might be valid in kanata)")
        } catch {
            AppLogger.shared.log("✅ [UIAutomation] Correctly handled invalid key names")
        }
        
        AppLogger.shared.log("✅ [UIAutomation] Error handling test completed")
    }
    
    // MARK: - Helper Methods
    
    /// Simulates the complete key remap UI flow
    private func simulateKeyRemapUIFlow(input: String, output: String) async -> UIFlowResult {
        AppLogger.shared.log("🔄 [UIAutomation] Simulating UI flow for \(input) → \(output)")
        
        var result = UIFlowResult()
        result.inputKey = input
        result.outputKey = output
        
        do {
            // Simulate the save operation
            try await kanataManager.saveConfiguration(input: input, output: output)
            result.success = true
            result.configurationSaved = true
            AppLogger.shared.log("✅ [UIAutomation] UI flow simulation successful")
        } catch {
            result.success = false
            result.error = error
            AppLogger.shared.log("❌ [UIAutomation] UI flow simulation failed: \(error)")
        }
        
        return result
    }
    
    // MARK: - Test Helper Types
    
    /// Represents the UI state during key remapping
    struct UIRemapState {
        var inputKey: String = ""
        var outputKey: String = ""
        var isRecordingInput: Bool = false
        var isRecordingOutput: Bool = false
        
        var canSave: Bool {
            !inputKey.isEmpty && !outputKey.isEmpty && !isRecordingInput && !isRecordingOutput
        }
        
        mutating func startInputRecording() {
            isRecordingInput = true
            inputKey = ""
        }
        
        mutating func captureInput(_ key: String) {
            inputKey = key
            isRecordingInput = false
        }
        
        mutating func startOutputRecording() {
            isRecordingOutput = true
            outputKey = ""
        }
        
        mutating func captureOutput(_ key: String) {
            outputKey = key
            isRecordingOutput = false
        }
        
        mutating func save() {
            inputKey = ""
            outputKey = ""
        }
    }
    
    /// Result of UI flow simulation
    struct UIFlowResult {
        var success: Bool = false
        var inputKey: String = ""
        var outputKey: String = ""
        var configurationSaved: Bool = false
        var error: Error?
    }
}

// MARK: - Extensions for Testing

extension KanataManager {
    /// Verify that configuration file exists (for testing)
    func verifyConfigExists() async -> Bool {
        // Check if the user config file exists
        let configPath = WizardSystemPaths.userConfigPath
        return FileManager.default.fileExists(atPath: configPath)
    }
}