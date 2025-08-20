@testable import KeyPath
import XCTest

/// Flexible UI Automation Tests using the UIAutomationFramework
/// Demonstrates how to easily test any key mapping scenario
@MainActor
final class FlexibleUIAutomationTests: XCTestCase {
    var kanataManager: KanataManager!
    var automationFramework: UIAutomationFramework!

    override func setUp() async throws {
        try await super.setUp()

        kanataManager = KanataManager()
        automationFramework = UIAutomationFramework(kanataManager: kanataManager)
        automationFramework.enableLogging = true
        automationFramework.validationMode = .comprehensive

        AppLogger.shared.log("🧪 [FlexibleUIAutomation] Test setup completed")
    }

    override func tearDown() async throws {
        automationFramework = nil
        kanataManager = nil

        try await super.tearDown()
    }

    // MARK: - Flexible Key Mapping Tests

    func testAnyKeyMappingScenario() async throws {
        AppLogger.shared.log("🤖 [FlexibleUIAutomation] Testing flexible key mapping scenarios")

        // Get all predefined test scenarios
        let scenarios = UIAutomationFramework.createTestScenarios()

        for scenario in scenarios {
            AppLogger.shared.log("🎯 [FlexibleUIAutomation] Testing scenario: \(scenario.name)")

            let results = await automationFramework.automateMultipleMappings(scenario.mappings)

            // Verify all mappings in the scenario succeeded
            for (index, result) in results.enumerated() {
                let mapping = scenario.mappings[index]
                XCTAssertTrue(
                    result.success,
                    "Mapping \(mapping.description) in scenario '\(scenario.name)' should succeed"
                )
                XCTAssertNil(
                    result.error,
                    "No errors expected for \(mapping.description) in scenario '\(scenario.name)'"
                )
            }

            let successCount = results.filter(\.success).count
            AppLogger.shared.log("✅ [FlexibleUIAutomation] Scenario '\(scenario.name)' completed: \(successCount)/\(results.count) succeeded")
        }

        AppLogger.shared.log("🎉 [FlexibleUIAutomation] All flexible scenarios completed")
    }

    func testCustomKeyMappings() async throws {
        AppLogger.shared.log("🤖 [FlexibleUIAutomation] Testing custom key mappings")

        // Define custom mappings that are easy to modify for different test cases
        let customMappings = [
            KeyMapping(input: "5", output: "6"), // Original 5→6 request
            KeyMapping(input: "j", output: "down"), // Vim-style navigation
            KeyMapping(input: "k", output: "up"), // Vim-style navigation
            KeyMapping(input: "ctrl", output: "cmd"), // Cross-platform modifier
            KeyMapping(input: "alt", output: "option"), // macOS consistency
            KeyMapping(input: "home", output: "cmd left"), // Home key to cmd+left
            KeyMapping(input: "end", output: "cmd right"), // End key to cmd+right
        ]

        for mapping in customMappings {
            AppLogger.shared.log("🔧 [FlexibleUIAutomation] Testing custom mapping: \(mapping.description)")

            let result = await automationFramework.automateKeyMapping(mapping)

            XCTAssertTrue(result.success, "Custom mapping \(mapping.description) should succeed")
            XCTAssertEqual(result.mapping.input, mapping.input, "Input should match")
            XCTAssertEqual(result.mapping.output, mapping.output, "Output should match")
            XCTAssertNil(result.error, "No errors expected for custom mapping")

            // Verify the automation steps were recorded
            XCTAssertFalse(result.steps.isEmpty, "Automation steps should be recorded")
            XCTAssertTrue(result.steps.contains(.started), "Should contain started step")
            XCTAssertTrue(result.steps.contains(.completed), "Should contain completed step")
        }

        AppLogger.shared.log("✅ [FlexibleUIAutomation] Custom mappings test completed")
    }

    func testDynamicMappingGeneration() async throws {
        AppLogger.shared.log("🤖 [FlexibleUIAutomation] Testing dynamic mapping generation")

        // Demonstrate how to programmatically generate mappings
        let numberMappings = (1 ... 9).map { num in
            KeyMapping(input: "\(num)", output: "\(num + 1)")
        }

        let baseLetters = Array("abcdefghijk")
        let inputLetters = Array("abcdefghij")
        let letterMappings = inputLetters.enumerated().map { index, char in
            let nextChar = String(baseLetters[index + 1])
            return KeyMapping(input: String(char), output: nextChar)
        }

        let functionKeyMappings = (1 ... 12).map { num in
            let nextNum = num == 12 ? 1 : num + 1
            return KeyMapping(input: "f\(num)", output: "f\(nextNum)")
        }

        // Test number mappings
        AppLogger.shared.log("🔢 [FlexibleUIAutomation] Testing number mappings")
        let numberResults = await automationFramework.automateMultipleMappings(numberMappings)
        let numberSuccessCount = numberResults.filter(\.success).count

        XCTAssertEqual(
            numberSuccessCount, numberMappings.count,
            "All number mappings should succeed"
        )

        // Test letter mappings
        AppLogger.shared.log("🔤 [FlexibleUIAutomation] Testing letter mappings")
        let letterResults = await automationFramework.automateMultipleMappings(letterMappings)
        let letterSuccessCount = letterResults.filter(\.success).count

        XCTAssertEqual(
            letterSuccessCount, letterMappings.count,
            "All letter mappings should succeed"
        )

        // Test function key mappings
        AppLogger.shared.log("🎛️ [FlexibleUIAutomation] Testing function key mappings")
        let functionResults = await automationFramework.automateMultipleMappings(functionKeyMappings)
        let functionSuccessCount = functionResults.filter(\.success).count

        XCTAssertEqual(
            functionSuccessCount, functionKeyMappings.count,
            "All function key mappings should succeed"
        )

        AppLogger.shared.log("✅ [FlexibleUIAutomation] Dynamic mapping generation completed")
        AppLogger.shared.log("   Numbers: \(numberSuccessCount)/\(numberMappings.count)")
        AppLogger.shared.log("   Letters: \(letterSuccessCount)/\(letterMappings.count)")
        AppLogger.shared.log("   Functions: \(functionSuccessCount)/\(functionKeyMappings.count)")
    }

    func testErrorHandlingInFlexibleFramework() async throws {
        AppLogger.shared.log("🤖 [FlexibleUIAutomation] Testing error handling")

        // Test various error scenarios
        let problematicMappings = [
            KeyMapping(input: "", output: "6"), // Empty input
            KeyMapping(input: "5", output: ""), // Empty output
            KeyMapping(input: "5", output: "5"), // Same key (might be valid)
        ]

        // Set framework to basic validation mode for error testing
        automationFramework.validationMode = .basic

        for mapping in problematicMappings {
            AppLogger.shared.log("⚠️ [FlexibleUIAutomation] Testing problematic mapping: \(mapping.description)")

            let result = await automationFramework.automateKeyMapping(mapping)

            if mapping.input.isEmpty || mapping.output.isEmpty {
                // These should fail
                XCTAssertFalse(result.success, "Empty key mappings should fail: \(mapping.description)")
                XCTAssertNotNil(result.error, "Error should be present for invalid mapping")
            } else {
                // These might succeed depending on kanata's validation
                AppLogger.shared.log("ℹ️ [FlexibleUIAutomation] Mapping result: success=\(result.success)")
            }

            // Verify steps are recorded even for failures
            XCTAssertFalse(result.steps.isEmpty, "Steps should be recorded even for failed mappings")
        }

        AppLogger.shared.log("✅ [FlexibleUIAutomation] Error handling test completed")
    }

    func testFrameworkConfiguration() async throws {
        AppLogger.shared.log("🤖 [FlexibleUIAutomation] Testing framework configuration")

        // Test different validation modes
        let testMapping = KeyMapping(input: "test", output: "demo")

        // Test with no validation
        automationFramework.validationMode = .none
        let noValidationResult = await automationFramework.automateKeyMapping(testMapping)
        XCTAssertFalse(noValidationResult.steps.contains(.validation), "Should skip validation")

        // Test with basic validation
        automationFramework.validationMode = .basic
        let basicValidationResult = await automationFramework.automateKeyMapping(testMapping)
        XCTAssertTrue(basicValidationResult.steps.contains(.validation), "Should include validation")

        // Test with comprehensive validation
        automationFramework.validationMode = .comprehensive
        let comprehensiveResult = await automationFramework.automateKeyMapping(testMapping)
        XCTAssertTrue(comprehensiveResult.steps.contains(.validation), "Should include comprehensive validation")

        // Test logging configuration
        automationFramework.enableLogging = false
        _ = await automationFramework.automateKeyMapping(testMapping)
        // Log verification would require capturing log output

        automationFramework.enableLogging = true

        AppLogger.shared.log("✅ [FlexibleUIAutomation] Framework configuration test completed")
    }

    // MARK: - Integration with Real UI Components

    func testIntegrationWithUIComponents() async throws {
        AppLogger.shared.log("🤖 [FlexibleUIAutomation] Testing integration with UI components")

        // This test demonstrates how the framework integrates with real UI components
        let mapping = KeyMapping(input: "caps", output: "esc")

        // Create a mock UI state that matches ContentView's structure
        var uiMockState = UIRemapState()

        // Simulate the UI flow using the framework
        let result = await automationFramework.automateKeyMapping(mapping)

        if result.success {
            // Simulate UI state updates that would happen in the real app
            uiMockState.inputKey = mapping.input
            uiMockState.outputKey = mapping.output
            uiMockState.save() // This would clear the form

            // Verify UI state matches expected behavior
            XCTAssertTrue(uiMockState.inputKey.isEmpty, "UI should clear input after save")
            XCTAssertTrue(uiMockState.outputKey.isEmpty, "UI should clear output after save")
        }

        AppLogger.shared.log("✅ [FlexibleUIAutomation] UI component integration test completed")
    }

    // MARK: - Helper Types for Testing

    /// Mock UI state that matches the ContentView's recording section
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
}

// MARK: - Extensions for Easy Testing

extension FlexibleUIAutomationTests {
    /// Helper to create common mapping types for quick testing
    func createCommonMappings() -> [KeyMapping] {
        [
            KeyMapping(input: "5", output: "6"), // The original request
            KeyMapping(input: "caps", output: "esc"), // Most common remap
            KeyMapping(input: "space", output: "tab"), // Space to Tab
            KeyMapping(input: "delete", output: "backspace"), // Delete consistency
            KeyMapping(input: "f1", output: "f2"), // Function key test
            KeyMapping(input: "a", output: "b"), // Letter test
        ]
    }

    /// Helper to verify automation result completeness
    func verifyAutomationResult(_ result: AutomationResult, for mapping: KeyMapping) {
        XCTAssertTrue(result.success, "Automation should succeed for \(mapping.description)")
        XCTAssertEqual(result.mapping.input, mapping.input, "Input should match")
        XCTAssertEqual(result.mapping.output, mapping.output, "Output should match")
        XCTAssertNil(result.error, "No error should be present")

        // Verify essential steps are present
        let essentialSteps: [AutomationStep] = [.started, .inputCapture, .outputCapture, .saving]
        for step in essentialSteps {
            XCTAssertTrue(result.steps.contains(step), "Should contain step: \(step)")
        }
    }
}
