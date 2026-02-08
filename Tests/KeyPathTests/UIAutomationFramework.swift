@testable import KeyPathAppKit
import KeyPathCore
import SwiftUI
@preconcurrency import XCTest

/// Generic UI Automation Framework for KeyPath
/// Provides reusable components for automating any key mapping scenario
@MainActor
public class UIAutomationFramework {
    // MARK: - Core Components

    private let kanataManager: RuntimeCoordinator
    private let keyboardCapture: MockKeyboardCapture
    private var automationLog: [AutomationStep] = []

    // MARK: - Configuration

    public var enableLogging: Bool = true
    public var timeout: TimeInterval = 10.0
    public var validationMode: ValidationMode = .comprehensive

    // MARK: - Initialization

    public init(kanataManager: RuntimeCoordinator, keyboardCapture: MockKeyboardCapture? = nil) {
        self.kanataManager = kanataManager
        self.keyboardCapture = keyboardCapture ?? MockKeyboardCapture()
    }

    // MARK: - High-Level Automation API

    /// Automate any key mapping with full UI simulation
    public func automateKeyMapping(_ mapping: KeyMapping) async -> AutomationResult {
        _ = AutomationContext(
            mapping: mapping,
            timestamp: Date(),
            framework: self
        )

        log(.started, "Automating \(mapping.description)")

        do {
            // Step 1: Prepare UI state
            let uiState = try await prepareUIState()

            // Step 2: Execute input capture
            let inputResult = await executeInputCapture(mapping.input, uiState: uiState)
            guard inputResult.success else {
                throw AutomationError.inputCaptureFailed(inputResult.error)
            }

            // Step 3: Execute output capture
            let outputResult = await executeOutputCapture(mapping.output, uiState: uiState)
            guard outputResult.success else {
                throw AutomationError.outputCaptureFailed(outputResult.error)
            }

            // Step 4: Save configuration
            let saveResult = await executeSave(mapping, uiState: uiState)
            guard saveResult.success else {
                throw AutomationError.saveFailed(saveResult.error)
            }

            // Step 5: Validate result
            if validationMode != .none {
                let validationResult = await validateMapping(mapping)
                if !validationResult.isValid, validationMode == .strict {
                    throw AutomationError.validationFailed(validationResult.errors)
                }
            }

            log(.completed, "Successfully automated \(mapping.description)")

            return AutomationResult(
                success: true,
                mapping: mapping,
                steps: automationLog,
                timestamp: Date()
            )

        } catch {
            log(.failed, "Automation failed: \(error)")
            return AutomationResult(
                success: false,
                mapping: mapping,
                steps: automationLog,
                timestamp: Date(),
                error: error
            )
        }
    }

    /// Automate multiple key mappings in sequence
    public func automateMultipleMappings(_ mappings: [KeyMapping]) async -> [AutomationResult] {
        var results: [AutomationResult] = []

        for mapping in mappings {
            let result = await automateKeyMapping(mapping)
            results.append(result)

            // Stop on first failure if in strict mode
            if !result.success, validationMode == .strict {
                break
            }
        }

        return results
    }

    /// Create common key mapping scenarios for testing
    public static func createTestScenarios() -> [KeyMappingScenario] {
        [
            KeyMappingScenario(
                name: "Basic Numeric Remaps",
                description: "Test basic number key remapping",
                mappings: [
                    KeyMapping(input: "1", output: "2"),
                    KeyMapping(input: "5", output: "6"),
                    KeyMapping(input: "9", output: "0")
                ]
            ),
            KeyMappingScenario(
                name: "Common System Remaps",
                description: "Test commonly used system key remaps",
                mappings: [
                    KeyMapping(input: "caps", output: "esc"),
                    KeyMapping(input: "space", output: "tab"),
                    KeyMapping(input: "delete", output: "backspace")
                ]
            ),
            KeyMappingScenario(
                name: "Function Key Remaps",
                description: "Test function key remapping",
                mappings: [
                    KeyMapping(input: "f1", output: "f2"),
                    KeyMapping(input: "f11", output: "f12"),
                    KeyMapping(input: "f5", output: "f6")
                ]
            ),
            KeyMappingScenario(
                name: "Letter Key Remaps",
                description: "Test letter key remapping",
                mappings: [
                    KeyMapping(input: "a", output: "b"),
                    KeyMapping(input: "x", output: "y"),
                    KeyMapping(input: "q", output: "w")
                ]
            ),
            KeyMappingScenario(
                name: "Complex Multi-Key Output",
                description: "Test mappings with multiple output keys",
                mappings: [
                    KeyMapping(input: "caps", output: "ctrl shift"),
                    KeyMapping(input: "tab", output: "alt space"),
                    KeyMapping(input: "esc", output: "cmd w")
                ]
            ),
            KeyMappingScenario(
                name: "Special Character Remaps",
                description: "Test special character key remapping",
                mappings: [
                    KeyMapping(input: "semicolon", output: "colon"),
                    KeyMapping(input: "comma", output: "period"),
                    KeyMapping(input: "slash", output: "backslash")
                ]
            )
        ]
    }

    // MARK: - Private Implementation

    private func prepareUIState() async throws -> UIStateSnapshot {
        log(.preparation, "Preparing UI state")

        // Simulate UI preparation
        return UIStateSnapshot(
            inputRecording: false,
            outputRecording: false,
            inputText: "",
            outputText: "",
            canSave: false
        )
    }

    private func executeInputCapture(_ input: String, uiState _: UIStateSnapshot) async
        -> CaptureResult
    {
        log(.inputCapture, "Capturing input key: \(input)")

        // Start input recording
        keyboardCapture.startCapture { capturedKey in
            self.log(.inputCaptured, "Input captured: \(capturedKey)")
        }

        // Simulate key press
        keyboardCapture.simulateKeyPress(input)

        // Stop recording
        keyboardCapture.stopCapture()

        return CaptureResult(success: true, capturedKey: input)
    }

    private func executeOutputCapture(_ output: String, uiState _: UIStateSnapshot) async
        -> CaptureResult
    {
        log(.outputCapture, "Capturing output key: \(output)")

        // Start output recording
        keyboardCapture.startContinuousCapture { capturedKey in
            self.log(.outputCaptured, "Output captured: \(capturedKey)")
        }

        // Simulate key press(es)
        let outputKeys = output.components(separatedBy: " ")
        for key in outputKeys {
            keyboardCapture.simulateKeyPress(key.trimmingCharacters(in: .whitespaces))
        }

        // Stop recording
        keyboardCapture.stopCapture()

        return CaptureResult(success: true, capturedKey: output)
    }

    private func executeSave(_ mapping: KeyMapping, uiState _: UIStateSnapshot) async -> SaveResult {
        log(.saving, "Saving mapping: \(mapping.input) → \(mapping.output)")

        do {
            try await kanataManager.saveConfiguration(input: mapping.input, output: mapping.output)
            log(.saved, "Mapping saved successfully")
            return SaveResult(success: true)
        } catch {
            log(.saveFailed, "Save failed: \(error)")
            return SaveResult(success: false, error: error)
        }
    }

    private func validateMapping(_ mapping: KeyMapping) async -> ValidationResult {
        log(.validation, "Validating mapping: \(mapping.description)")

        var validation = ValidationResult()

        // Check configuration file exists
        let configPath = "\(NSHomeDirectory())/Library/Application Support/KeyPath/keypath.kbd"
        let configExists = FileManager.default.fileExists(atPath: configPath)
        if !configExists {
            validation.errors.append("Configuration file does not exist")
        }

        // Additional validation logic can be added here

        validation.isValid = validation.errors.isEmpty

        if validation.isValid {
            log(.validationPassed, "Mapping validation passed")
        } else {
            log(
                .validationFailed, "Mapping validation failed: \(validation.errors.joined(separator: ", "))"
            )
        }

        return validation
    }

    private func log(_ step: AutomationStep, _ message: String) {
        if enableLogging {
            AppLogger.shared.log("🤖 [UIFramework] \(message)")
        }
        automationLog.append(step)
    }
}

// MARK: - Supporting Types

/// Extension to add description property for test compatibility
/// Represents a key mapping configuration
/// Note: KeyMapping is imported from the main KeyPath module via @testable import
extension KeyMapping {
    var description: String {
        "\(input) → \(output)"
    }
}

/// A scenario containing multiple related key mappings
public struct KeyMappingScenario {
    public let name: String
    public let description: String
    public let mappings: [KeyMapping]

    public init(name: String, description: String, mappings: [KeyMapping]) {
        self.name = name
        self.description = description
        self.mappings = mappings
    }
}

/// Context for an automation session
public struct AutomationContext {
    public let mapping: KeyMapping
    public let timestamp: Date
    public let framework: UIAutomationFramework
}

/// Result of an automation run
public struct AutomationResult {
    public let success: Bool
    public let mapping: KeyMapping
    public let steps: [AutomationStep]
    public let timestamp: Date
    public let error: Error?

    public init(
        success: Bool, mapping: KeyMapping, steps: [AutomationStep], timestamp: Date,
        error: Error? = nil
    ) {
        self.success = success
        self.mapping = mapping
        self.steps = steps
        self.timestamp = timestamp
        self.error = error
    }
}

/// Steps in the automation process
public enum AutomationStep {
    case started
    case preparation
    case inputCapture
    case inputCaptured
    case outputCapture
    case outputCaptured
    case saving
    case saved
    case saveFailed
    case validation
    case validationPassed
    case validationFailed
    case completed
    case failed
}

/// Validation modes for automation
public enum ValidationMode {
    case none
    case basic
    case comprehensive
    case strict
}

/// UI state snapshot
public struct UIStateSnapshot {
    public let inputRecording: Bool
    public let outputRecording: Bool
    public let inputText: String
    public let outputText: String
    public let canSave: Bool
}

/// Result of a capture operation
public struct CaptureResult {
    public let success: Bool
    public let capturedKey: String?
    public let error: Error?

    public init(success: Bool, capturedKey: String? = nil, error: Error? = nil) {
        self.success = success
        self.capturedKey = capturedKey
        self.error = error
    }
}

/// Result of a save operation
public struct SaveResult {
    public let success: Bool
    public let error: Error?

    public init(success: Bool, error: Error? = nil) {
        self.success = success
        self.error = error
    }
}

/// Result of validation
public struct ValidationResult {
    public var isValid: Bool = true
    public var errors: [String] = []
}

/// Automation errors
public enum AutomationError: Error {
    case inputCaptureFailed(Error?)
    case outputCaptureFailed(Error?)
    case saveFailed(Error?)
    case validationFailed([String])
    case timeout
    case uiStateInvalid
}

// MARK: - Enhanced MockKeyboardCapture

/// Enhanced mock keyboard capture for automation framework
public class MockKeyboardCapture: KeyboardCapture {
    private var inputCallback: ((String) -> Void)?
    private var continuousCallback: ((String) -> Void)?
    private var simulationDelay: TimeInterval = 0.1

    override public func startCapture(callback: @escaping (String) -> Void) {
        inputCallback = callback
        AppLogger.shared.log("🎭 [MockKeyCapture] Started input capture")
    }

    override public func startContinuousCapture(callback: @escaping (String) -> Void) {
        continuousCallback = callback
        AppLogger.shared.log("🎭 [MockKeyCapture] Started continuous capture")
    }

    override public func stopCapture() {
        inputCallback = nil
        continuousCallback = nil
        AppLogger.shared.log("🎭 [MockKeyCapture] Stopped capture")
    }

    public func simulateKeyPress(_ keyName: String) {
        // Add slight delay to simulate realistic timing
        DispatchQueue.main.asyncAfter(deadline: .now() + simulationDelay) {
            self.inputCallback?(keyName)
            self.continuousCallback?(keyName)
            AppLogger.shared.log("🎭 [MockKeyCapture] Simulated key press: \(keyName)")
        }
    }

    public func setSimulationDelay(_ delay: TimeInterval) {
        simulationDelay = delay
    }
}
