import XCTest
@testable import KeyPath

final class KeyPathChatControllerTests: XCTestCase {
    var controller: KeyPathChatController!
    var mockSecurityManager: MockSecurityManager!
    var mockRuleHistory: MockRuleHistory!
    var mockModelProvider: MockAnthropicModelProvider!
    var mockKanataInstaller: MockKanataInstaller!
    
    override func setUp() {
        super.setUp()
        
        mockSecurityManager = MockSecurityManager()
        mockRuleHistory = MockRuleHistory()
        mockModelProvider = MockAnthropicModelProvider()
        mockKanataInstaller = MockKanataInstaller()
        
        controller = KeyPathChatController(
            securityManager: mockSecurityManager,
            ruleHistory: mockRuleHistory,
            modelProvider: mockModelProvider,
            kanataInstaller: mockKanataInstaller
        )
    }
    
    override func tearDown() {
        controller = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertTrue(controller.messages.isEmpty)
        XCTAssertFalse(controller.isResponding)
        XCTAssertTrue(controller.errorMessage.isEmpty)
        XCTAssertFalse(controller.showErrorAlert)
        XCTAssertNil(controller.pendingRemappingDescription)
        XCTAssertNil(controller.generatedRule)
        XCTAssertFalse(controller.showRulePreview)
    }
    
    // MARK: - Send Message Tests
    
    func testSendMessageWithEmptyInput() async {
        await controller.sendMessage("")
        await controller.sendMessage("   ")
        await controller.sendMessage("\n\t")
        
        XCTAssertTrue(controller.messages.isEmpty)
        XCTAssertFalse(controller.isResponding)
    }
    
    func testSendMessageSuccessWithRule() async {
        let expectation = self.expectation(description: "Send message success")
        
        // Set up mock response
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Caps to Escape",
            description: "Maps Caps Lock to Escape"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps esc)",
            confidence: .high,
            explanation: "Maps Caps Lock to Escape"
        )
        
        mockModelProvider.mockResponse = .rule(rule)
        
        await controller.sendMessage("Map caps lock to escape")
        
        // Wait a moment for async operations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.controller.messages.count, 2)
            XCTAssertEqual(self.controller.messages[0].role, .user)
            XCTAssertEqual(self.controller.messages[0].displayText, "Map caps lock to escape")
            XCTAssertEqual(self.controller.messages[1].role, .assistant)
            XCTAssertTrue(self.controller.messages[1].isRule)
            XCTAssertFalse(self.controller.isResponding)
            expectation.fulfill()
        }
        
        await waitForExpectations(timeout: 1.0)
    }
    
    func testSendMessageSuccessWithClarification() async {
        let expectation = self.expectation(description: "Send message clarification")
        
        mockModelProvider.mockResponse = .clarification("Could you please specify which key you want to remap?")
        
        await controller.sendMessage("I want to remap something")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.controller.messages.count, 2)
            XCTAssertEqual(self.controller.messages[1].displayText, "Could you please specify which key you want to remap?")
            XCTAssertFalse(self.controller.messages[1].isRule)
            XCTAssertFalse(self.controller.isResponding)
            expectation.fulfill()
        }
        
        await waitForExpectations(timeout: 1.0)
    }
    
    func testSendMessageNetworkError() async {
        let expectation = self.expectation(description: "Network error handling")
        
        mockModelProvider.mockError = URLError(.networkConnectionLost)
        
        await controller.sendMessage("Test message")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.controller.messages.count, 1) // Only user message remains
            XCTAssertTrue(self.controller.showErrorAlert)
            XCTAssertTrue(self.controller.errorMessage.contains("Network Connection Error"))
            XCTAssertFalse(self.controller.isResponding)
            expectation.fulfill()
        }
        
        await waitForExpectations(timeout: 1.0)
    }
    
    func testSendMessageAPIKeyError() async {
        let expectation = self.expectation(description: "API key error handling")
        
        mockModelProvider.mockError = NSError(domain: "Anthropic", code: 401, userInfo: [NSLocalizedDescriptionKey: "x-api-key authentication failed"])
        
        await controller.sendMessage("Test message")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.controller.showErrorAlert)
            XCTAssertTrue(self.controller.errorMessage.contains("API Key Missing or Invalid"))
            XCTAssertTrue(self.controller.errorMessage.contains("sk-ant-api"))
            XCTAssertFalse(self.controller.isResponding)
            expectation.fulfill()
        }
        
        await waitForExpectations(timeout: 1.0)
    }
    
    func testSendMessageRateLimitError() async {
        let expectation = self.expectation(description: "Rate limit error handling")
        
        mockModelProvider.mockError = NSError(domain: "Anthropic", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limit exceeded"])
        
        await controller.sendMessage("Test message")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.controller.showErrorAlert)
            XCTAssertTrue(self.controller.errorMessage.contains("Rate Limit Exceeded"))
            XCTAssertFalse(self.controller.isResponding)
            expectation.fulfill()
        }
        
        await waitForExpectations(timeout: 1.0)
    }
    
    func testSendMessageWithNonAnthropicProvider() async {
        let expectation = self.expectation(description: "Non-Anthropic provider error")
        
        let nonAnthropicProvider = MockChatModelProvider()
        controller = KeyPathChatController(
            securityManager: mockSecurityManager,
            ruleHistory: mockRuleHistory,
            modelProvider: nonAnthropicProvider,
            kanataInstaller: mockKanataInstaller
        )
        
        await controller.sendMessage("Test message")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.controller.showErrorAlert)
            XCTAssertTrue(self.controller.errorMessage.contains("KeyPath requires Anthropic Claude"))
            XCTAssertFalse(self.controller.isResponding)
            expectation.fulfill()
        }
        
        await waitForExpectations(timeout: 1.0)
    }
    
    // MARK: - Install Rule Tests
    
    func testInstallRuleSuccess() {
        let expectation = self.expectation(description: "Install rule success")
        
        mockSecurityManager.canInstallRulesReturn = true
        mockKanataInstaller.validateResult = .success(true)
        mockKanataInstaller.installResult = .success("/path/to/backup")
        
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias a b)",
            confidence: .high,
            explanation: "Test rule"
        )
        
        controller.installRule(rule)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.controller.messages.count, 1)
            XCTAssertTrue(self.controller.messages[0].displayText.contains("✅ Rule installed successfully"))
            XCTAssertTrue(self.mockRuleHistory.addRuleCalled)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testInstallRuleSecurityBlocked() {
        mockSecurityManager.canInstallRulesReturn = false
        
        let rule = createTestRule()
        controller.installRule(rule)
        
        XCTAssertEqual(controller.messages.count, 1)
        XCTAssertTrue(controller.messages[0].displayText.contains("⚠️ Kanata setup required"))
        XCTAssertFalse(mockKanataInstaller.validateCalled)
    }
    
    func testInstallRuleValidationFailure() {
        let expectation = self.expectation(description: "Validation failure")
        
        mockSecurityManager.canInstallRulesReturn = true
        mockKanataInstaller.validateResult = .failure(KanataValidationError.validationFailed("Invalid syntax"))
        
        let rule = createTestRule()
        controller.installRule(rule)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.controller.messages.count, 1)
            XCTAssertTrue(self.controller.messages[0].displayText.contains("❌ Validation failed"))
            XCTAssertFalse(self.mockKanataInstaller.installCalled)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testInstallRuleInstallationFailure() {
        let expectation = self.expectation(description: "Installation failure")
        
        mockSecurityManager.canInstallRulesReturn = true
        mockKanataInstaller.validateResult = .success(true)
        mockKanataInstaller.installResult = .failure(KanataValidationError.writeFailed("Write failed"))
        
        let rule = createTestRule()
        controller.installRule(rule)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(self.controller.messages.count, 1)
            XCTAssertTrue(self.controller.messages[0].displayText.contains("❌ Installation failed"))
            XCTAssertFalse(self.mockRuleHistory.addRuleCalled)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    // MARK: - Undo Last Rule Tests
    
    func testUndoLastRuleSuccess() {
        let expectation = self.expectation(description: "Undo success")
        
        let ruleEntry = RuleHistoryItem(
            rule: createTestRule(),
            timestamp: Date(),
            backupPath: "/path/to/backup"
        )
        mockRuleHistory.lastRule = ruleEntry
        mockKanataInstaller.undoResult = .success(true)
        
        controller.undoLastRule()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.controller.messages.count, 1)
            XCTAssertTrue(self.controller.messages[0].displayText.contains("✅ Successfully undid"))
            XCTAssertTrue(self.mockRuleHistory.removeLastRuleCalled)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testUndoLastRuleNoRules() {
        mockRuleHistory.lastRule = nil
        
        controller.undoLastRule()
        
        XCTAssertTrue(controller.messages.isEmpty)
        XCTAssertFalse(mockKanataInstaller.undoCalled)
    }
    
    func testUndoLastRuleFailure() {
        let expectation = self.expectation(description: "Undo failure")
        
        let ruleEntry = RuleHistoryItem(
            rule: createTestRule(),
            timestamp: Date(),
            backupPath: "/path/to/backup"
        )
        mockRuleHistory.lastRule = ruleEntry
        mockKanataInstaller.undoResult = .failure(KanataValidationError.writeFailed("Restore failed"))
        
        controller.undoLastRule()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.controller.messages.count, 1)
            XCTAssertTrue(self.controller.messages[0].displayText.contains("❌ Failed to undo"))
            XCTAssertFalse(self.mockRuleHistory.removeLastRuleCalled)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    // MARK: - Reset Conversation Tests
    
    func testResetConversation() {
        // Set up some state
        controller.messages.append(KeyPathMessage(role: .user, text: "Test"))
        controller.pendingRemappingDescription = "Test description"
        controller.generatedRule = createTestRule()
        controller.isResponding = true
        
        controller.resetConversation()
        
        XCTAssertTrue(controller.messages.isEmpty)
        XCTAssertNil(controller.pendingRemappingDescription)
        XCTAssertNil(controller.generatedRule)
        XCTAssertFalse(controller.isResponding)
    }
    
    // MARK: - Welcome Message Tests
    
    func testShowWelcomeMessage() {
        let expectation = self.expectation(description: "Welcome message")
        expectation.expectedFulfillmentCount = 2
        
        controller.showWelcomeMessage()
        
        // Check immediate logo message
        XCTAssertEqual(controller.messages.count, 1)
        XCTAssertEqual(controller.messages[0].displayText, "LOGO_VIEW")
        expectation.fulfill()
        
        // Check welcome text after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertEqual(self.controller.messages.count, 2)
            XCTAssertTrue(self.controller.messages[1].displayText.contains("Welcome to KeyPath"))
            XCTAssertTrue(self.controller.messages[1].displayText.contains("Simple substitutions"))
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
    }
    
    // MARK: - Error Message Tests
    
    func testGetUserFriendlyErrorMessageAuthentication() {
        let authError = NSError(domain: "Test", code: 401, userInfo: [NSLocalizedDescriptionKey: "x-api-key header is required"])
        let friendlyMessage = controller.getUserFriendlyErrorMessage(from: authError)
        
        XCTAssertTrue(friendlyMessage.contains("API Key Missing or Invalid"))
        XCTAssertTrue(friendlyMessage.contains("sk-ant-api"))
    }
    
    func testGetUserFriendlyErrorMessageNetwork() {
        let networkError = URLError(.networkConnectionLost)
        let friendlyMessage = controller.getUserFriendlyErrorMessage(from: networkError)
        
        XCTAssertTrue(friendlyMessage.contains("Network Connection Error"))
        XCTAssertTrue(friendlyMessage.contains("internet connection"))
    }
    
    func testGetUserFriendlyErrorMessageRateLimit() {
        let rateLimitError = NSError(domain: "Test", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limit exceeded"])
        let friendlyMessage = controller.getUserFriendlyErrorMessage(from: rateLimitError)
        
        XCTAssertTrue(friendlyMessage.contains("Rate Limit Exceeded"))
        XCTAssertTrue(friendlyMessage.contains("too many requests"))
    }
    
    func testGetUserFriendlyErrorMessageInvalidRequest() {
        let invalidError = NSError(domain: "Test", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid request format"])
        let friendlyMessage = controller.getUserFriendlyErrorMessage(from: invalidError)
        
        XCTAssertTrue(friendlyMessage.contains("Invalid Request"))
        XCTAssertTrue(friendlyMessage.contains("rephrasing"))
    }
    
    func testGetUserFriendlyErrorMessageGeneric() {
        let genericError = NSError(domain: "Test", code: 500, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
        let friendlyMessage = controller.getUserFriendlyErrorMessage(from: genericError)
        
        XCTAssertTrue(friendlyMessage.contains("An error occurred"))
        XCTAssertTrue(friendlyMessage.contains("Something went wrong"))
        XCTAssertTrue(friendlyMessage.contains("API key in Settings"))
    }
    
    // MARK: - Helper Methods
    
    private func createTestRule() -> KanataRule {
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        return KanataRule(
            visualization: visualization,
            kanataRule: "(defalias a b)",
            confidence: .high,
            explanation: "Test rule"
        )
    }
}

// MARK: - Mock Classes

class MockSecurityManager: SecurityManager {
    var canInstallRulesReturn = true
    
    override func canInstallRules() -> Bool {
        return canInstallRulesReturn
    }
}

class MockRuleHistory: RuleHistory {
    var addRuleCalled = false
    var removeLastRuleCalled = false
    var lastRule: RuleHistoryItem?
    
    override func addRule(_ rule: KanataRule, backupPath: String) {
        addRuleCalled = true
        lastRule = RuleHistoryItem(rule: rule, timestamp: Date(), backupPath: backupPath)
    }
    
    override func removeLastRule() {
        removeLastRuleCalled = true
        lastRule = nil
    }
    
    override func getLastRule() -> RuleHistoryItem? {
        return lastRule
    }
}

class MockAnthropicModelProvider: KeyPathTestableProvider {
    var mockResponse: DirectResponse?
    var mockError: Error?
    
    func sendMessage(_ prompt: String) async throws -> String {
        if let error = mockError {
            throw error
        }
        return "Mock response"
    }
    
    func sendConversation(_ messages: [KeyPathMessage]) async throws -> String {
        if let error = mockError {
            throw error
        }
        return "Mock conversation response"
    }
    
    func streamMessage(_ prompt: String, onUpdate: @escaping (String) -> Void) async throws {
        if let error = mockError {
            throw error
        }
        onUpdate("Mock stream chunk")
    }
    
    func sendDirectMessageWithHistory(_ messages: [KeyPathMessage]) async throws -> DirectResponse {
        if let error = mockError {
            throw error
        }
        
        return mockResponse ?? .clarification("Default mock response")
    }
}

class MockChatModelProvider: ChatModelProvider {
    func sendMessage(_ prompt: String) async throws -> String {
        return "Mock response"
    }
    
    func sendConversation(_ messages: [KeyPathMessage]) async throws -> String {
        return "Mock conversation response"
    }
    
    func streamMessage(_ prompt: String, onUpdate: @escaping (String) -> Void) async throws {
        onUpdate("Mock stream chunk")
    }
}

class MockKanataInstaller: KanataInstaller {
    var validateCalled = false
    var installCalled = false
    var undoCalled = false
    
    var validateResult: Result<Bool, KanataValidationError> = .success(true)
    var installResult: Result<String, KanataValidationError> = .success("/mock/backup/path")
    var undoResult: Result<Bool, KanataValidationError> = .success(true)
    
    override func validateRule(_ rule: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        validateCalled = true
        completion(validateResult)
    }
    
    override func installRule(_ rule: KanataRule, completion: @escaping (Result<String, KanataValidationError>) -> Void) {
        installCalled = true
        completion(installResult)
    }
    
    override func undoLastRule(backupPath: String, completion: @escaping (Result<Bool, KanataValidationError>) -> Void) {
        undoCalled = true
        completion(undoResult)
    }
}