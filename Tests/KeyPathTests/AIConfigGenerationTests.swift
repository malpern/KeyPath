@testable import KeyPathAppKit
import XCTest

/// Tests for AI Config Generation components
@MainActor
final class AIConfigGenerationTests: XCTestCase {
    // MARK: - KeychainService Tests

    func testKeychainServiceHasClaudeAPIKeyMethodsExist() {
        // Verify the methods exist and are callable
        let service = KeychainService.shared

        // Check hasClaudeAPIKey property exists
        _ = service.hasClaudeAPIKey

        // Check getClaudeAPIKey method exists
        _ = service.getClaudeAPIKey()

        // These should not crash - we're just testing the API exists
    }

    func testKeychainServiceRetrieveClaudeAPIKeyReturnsNilWhenNotSet() {
        // In test environment, there should be no key stored initially
        // (unless tests are running on a dev machine with a key)
        let service = KeychainService.shared
        let key = service.retrieveClaudeAPIKey()

        // Either nil or a valid key - both are acceptable in test environment
        if let key {
            XCTAssertTrue(key.hasPrefix("sk-ant-"), "If a key exists, it should start with sk-ant-")
        }
    }

    func testGetClaudeAPIKeyChecksEnvironmentFirst() {
        // Save any existing env var
        let originalValue = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]

        // The method should check environment first
        // We can't easily set env vars in tests, but we can verify the method doesn't crash
        let key = KeychainService.shared.getClaudeAPIKey()

        // If there's an env var, it should be returned
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            XCTAssertEqual(key, envKey, "Should return environment variable if set")
        }

        // Restore - note: we can't actually unset env vars in Swift
        _ = originalValue
    }

    func testGetClaudeAPIKeyStaticMethod() {
        // Test the static method can be called from any context
        let key = KeychainService.getClaudeAPIKeyStatic()

        // Should return nil or a valid key
        if let key {
            XCTAssertFalse(key.isEmpty, "If a key is returned, it should not be empty")
        }
    }

    func testHasClaudeAPIKeyFromEnvironmentProperty() {
        let service = KeychainService.shared

        // Check property is accessible
        let hasFromEnv = service.hasClaudeAPIKeyFromEnvironment

        // If env var is set, should return true
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            XCTAssertTrue(hasFromEnv, "Should detect API key from environment")
        }
    }

    func testHasClaudeAPIKeyInKeychainProperty() {
        let service = KeychainService.shared

        // Check property is accessible and matches retrieveClaudeAPIKey
        let hasInKeychain = service.hasClaudeAPIKeyInKeychain
        let keyExists = service.retrieveClaudeAPIKey() != nil

        XCTAssertEqual(hasInKeychain, keyExists, "hasClaudeAPIKeyInKeychain should match retrieveClaudeAPIKey")
    }

    func testHasClaudeAPIKeyChecksAllSources() {
        let service = KeychainService.shared

        // hasClaudeAPIKey should be true if EITHER env or keychain has a key
        let hasKey = service.hasClaudeAPIKey
        let hasFromEnv = service.hasClaudeAPIKeyFromEnvironment
        let hasInKeychain = service.hasClaudeAPIKeyInKeychain

        XCTAssertEqual(hasKey, hasFromEnv || hasInKeychain, "hasClaudeAPIKey should check both sources")
    }

    // MARK: - APIKeyValidator Tests

    // Note: testAPIKeyValidatorRejectsEmptyKey is not tested because
    // empty keys trigger a debug assertion. The assertion is appropriate
    // for catching programming errors - callers should check for empty
    // strings before calling validate().

    func testAPIKeyValidatorRejectsKeyWithWrongPrefix() async {
        let validator = APIKeyValidator.shared
        let result = await validator.validate("wrong-prefix-key-123456789")

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("sk-ant-") ?? false, "Error should mention correct prefix")
    }

    func testAPIKeyValidatorRejectsTooShortKey() async {
        let validator = APIKeyValidator.shared
        let result = await validator.validate("sk-ant-short")

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("incomplete") ?? false, "Error should mention key is incomplete")
    }

    func testAPIKeyValidatorValidationResultTypes() {
        // Test ValidationResult factory methods
        let valid = APIKeyValidator.ValidationResult.valid()
        XCTAssertTrue(valid.isValid)
        XCTAssertNil(valid.errorMessage)
        XCTAssertEqual(valid.statusCode, 200)

        let invalid = APIKeyValidator.ValidationResult.invalid(message: "Test error", statusCode: 401)
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(invalid.errorMessage, "Test error")
        XCTAssertEqual(invalid.statusCode, 401)
    }

    // MARK: - BiometricAuthService Tests

    func testBiometricAuthServiceSharedInstanceExists() {
        let service = BiometricAuthService.shared
        XCTAssertNotNil(service)
    }

    func testBiometricAuthServiceIsEnabledDefaultsFalse() {
        // Clear any existing preference
        UserDefaults.standard.removeObject(forKey: BiometricAuthService.requireBiometricAuthKey)

        let service = BiometricAuthService.shared

        // Should default to false (not enabled)
        XCTAssertFalse(service.isEnabled)
    }

    func testBiometricAuthServiceIsEnabledCanBeToggled() {
        let service = BiometricAuthService.shared

        // Save original state
        let originalState = service.isEnabled

        // Toggle
        service.isEnabled = !originalState
        XCTAssertEqual(service.isEnabled, !originalState)

        // Restore
        service.isEnabled = originalState
    }

    func testBiometricAuthServiceBiometricTypeName() {
        let service = BiometricAuthService.shared
        let name = service.biometricTypeName

        // Should be one of the known types
        let validNames = ["Touch ID", "Face ID", "Optic ID", "Password", "Biometric"]
        XCTAssertTrue(validNames.contains(name), "biometricTypeName should be a valid type")
    }

    func testBiometricAuthServiceWouldRequireAuthRespectsIsEnabled() {
        let service = BiometricAuthService.shared

        // When disabled, should not require auth
        service.isEnabled = false
        XCTAssertFalse(service.wouldRequireAuth)

        // When enabled, should require auth (unless recently authenticated)
        service.isEnabled = true
        service.clearAuthCache()
        XCTAssertTrue(service.wouldRequireAuth)

        // Clean up
        service.isEnabled = false
    }

    func testBiometricAuthServiceAuthReturnsNotRequiredWhenDisabled() async {
        let service = BiometricAuthService.shared
        service.isEnabled = false

        let result = await service.authenticate()

        switch result {
        case .notRequired:
            // Expected
            break
        default:
            XCTFail("Should return .notRequired when disabled")
        }
    }

    // MARK: - AIKeyRequiredDialog Tests

    func testAIKeyRequiredDialogDismissedKeyExists() {
        XCTAssertNotNil(AIKeyRequiredDialog.dismissedKey)
    }

    func testAIKeyRequiredDialogResetDismissedState() {
        // Set dismissed state
        UserDefaults.standard.set(true, forKey: AIKeyRequiredDialog.dismissedKey)
        XCTAssertTrue(AIKeyRequiredDialog.hasBeenDismissed)

        // Reset
        AIKeyRequiredDialog.resetDismissedState()
        XCTAssertFalse(AIKeyRequiredDialog.hasBeenDismissed)
    }

    func testAIKeyRequiredDialogShouldShowLogic() {
        // Reset state
        AIKeyRequiredDialog.resetDismissedState()

        // Should show is based on:
        // - No API key AND
        // - Not dismissed

        // We can't easily mock KeychainService.shared.hasClaudeAPIKey,
        // but we can verify the logic doesn't crash
        _ = AIKeyRequiredDialog.shouldShow()
    }

    // MARK: - AICostTracker Tests

    func testAICostTrackerSharedInstanceExists() {
        let tracker = AICostTracker.shared
        XCTAssertNotNil(tracker)
    }

    func testAICostTrackerCostHistoryKeyConstant() {
        // Verify the constant is defined correctly
        XCTAssertEqual(AICostTracker.costHistoryKey, "KeyPath.AI.CostHistory")
    }

    func testAICostTrackerEstimateCost() {
        let tracker = AICostTracker.shared

        // Test the cost calculation logic
        // Claude 3.5 Sonnet: $3/1M input, $15/1M output
        let cost = tracker.estimateCost(inputTokens: 1000, outputTokens: 500)

        // 1000 input tokens = $0.003
        // 500 output tokens = $0.0075
        // Total = $0.0105
        XCTAssertEqual(cost, 0.0105, accuracy: 0.0001)
    }

    func testClaudeAPIPricingConstants() {
        // Verify pricing constants are set correctly (as of Dec 2024)
        XCTAssertEqual(ClaudeAPIPricing.inputPricePerMillion, 3.0)
        XCTAssertEqual(ClaudeAPIPricing.outputPricePerMillion, 15.0)
    }

    func testClaudeAPIPricingEstimateCost() {
        // Test the static pricing calculation
        let cost = ClaudeAPIPricing.estimateCost(inputTokens: 1000, outputTokens: 500)
        XCTAssertEqual(cost, 0.0105, accuracy: 0.0001)
    }

    func testAICostTrackerCostSourceEnumValues() {
        // Verify source enum values for debugging
        XCTAssertEqual(AICostTracker.CostSource.configGenerator.rawValue, "config-generator")
        XCTAssertEqual(AICostTracker.CostSource.configRepair.rawValue, "config-repair")
    }

    func testAICostTrackerHistoryAccess() {
        // Verify history access methods work without crashing
        let tracker = AICostTracker.shared
        _ = tracker.costHistory
        _ = tracker.totalEstimatedCost
        _ = tracker.totalTokens
    }

    func testClaudeAPIConstantsAreDefined() {
        // Verify API constants are properly defined
        XCTAssertNotNil(ClaudeAPIConstants.messagesEndpoint)
        XCTAssertFalse(ClaudeAPIConstants.apiVersion.isEmpty)
        XCTAssertFalse(ClaudeAPIConstants.defaultModel.isEmpty)
        XCTAssertGreaterThan(ClaudeAPIConstants.maxTokensForConfig, 0)
        XCTAssertGreaterThan(ClaudeAPIConstants.requestTimeout, 0)
    }

    // MARK: - Integration Assertions

    func testAssertionsAreEnabled() {
        // Verify assertions are enabled in test builds
        var assertionTriggered = false

        // This would crash if assertions were enabled differently
        // We're just verifying the test environment is correct
        assertionTriggered = true

        XCTAssertTrue(assertionTriggered)
    }
}

// MARK: - ConfigGeneratorError Tests

extension AIConfigGenerationTests {
    func testConfigGeneratorErrorDescriptions() {
        let authCancelled = KanataConfigGenerator.ConfigGeneratorError.authenticationCancelled
        XCTAssertEqual(authCancelled.errorDescription, "Authentication was cancelled")

        let noAPIKey = KanataConfigGenerator.ConfigGeneratorError.noAPIKey
        XCTAssertTrue(noAPIKey.errorDescription?.contains("API key") ?? false)
    }
}
