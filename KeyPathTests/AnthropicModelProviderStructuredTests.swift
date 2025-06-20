import XCTest
@testable import KeyPath

final class AnthropicModelProviderStructuredTests: XCTestCase {
    var provider: AnthropicModelProvider!
    var mockURLSession: MockURLSession!
    
    override func setUp() {
        super.setUp()
        
        // Set up a mock API key for testing
        setenv("ANTHROPIC_API_KEY", "test-api-key", 1)
        
        provider = AnthropicModelProvider(
            systemInstructions: "You are a helpful assistant.",
            temperature: 0.7
        )
        
        mockURLSession = MockURLSession()
    }
    
    override func tearDown() {
        unsetenv("ANTHROPIC_API_KEY")
        super.tearDown()
    }
    
    // MARK: - DirectResponse Enum Tests
    
    func testDirectResponseRuleCase() {
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps esc)",
            confidence: .high,
            explanation: "Test rule"
        )
        
        let response = DirectResponse.rule(rule)
        
        if case .rule(let extractedRule) = response {
            XCTAssertEqual(extractedRule.kanataRule, "(defalias caps esc)")
            XCTAssertEqual(extractedRule.explanation, "Test rule")
        } else {
            XCTFail("Expected rule case")
        }
    }
    
    func testDirectResponseClarificationCase() {
        let response = DirectResponse.clarification("Could you please clarify what key you want to remap?")
        
        if case .clarification(let message) = response {
            XCTAssertEqual(message, "Could you please clarify what key you want to remap?")
        } else {
            XCTFail("Expected clarification case")
        }
    }
    
    // MARK: - sendDirectMessageWithHistory Tests
    
    func testSendDirectMessageWithHistorySuccess() async {
        let expectation = self.expectation(description: "Direct message with history completion")
        
        // Create test messages with last message being user text
        let messages = [
            KeyPathMessage(role: .user, text: "Hello"),
            KeyPathMessage(role: .assistant, text: "Hi there!"),
            KeyPathMessage(role: .user, text: "Map caps lock to escape")
        ]
        
        // Mock successful response with JSON rule
        let mockResponse = """
        ```json
        {
          "visualization": {
            "behavior": {
              "type": "simpleRemap",
              "data": {"from": "caps", "toKey": "esc"}
            },
            "title": "Caps Lock to Escape",
            "description": "Maps Caps Lock to Escape"
          },
          "kanata_rule": "(defalias caps esc)",
          "confidence": "high",
          "explanation": "Maps the Caps Lock key to Escape"
        }
        ```
        """
        
        mockURLSession.data = """
        {
            "content": [{"text": "\(mockResponse)"}],
            "role": "assistant"
        }
        """.data(using: .utf8)!
        
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        let task = Task {
            do {
                let response = try await provider.sendDirectMessageWithHistory(messages)
                
                if case .rule(let rule) = response {
                    XCTAssertEqual(rule.kanataRule, "(defalias caps esc)")
                    XCTAssertEqual(rule.explanation, "Maps the Caps Lock key to Escape")
                    XCTAssertEqual(rule.confidence, .high)
                    expectation.fulfill()
                } else {
                    XCTFail("Expected rule response")
                    expectation.fulfill()
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 2.0) { _ in
            task.cancel()
        }
    }
    
    func testSendDirectMessageWithHistoryClarification() async {
        let expectation = self.expectation(description: "Direct message clarification")
        
        let messages = [
            KeyPathMessage(role: .user, text: "I want to remap something")
        ]
        
        // Mock response that can't be parsed as JSON rule
        let mockResponse = "Could you please specify which key you want to remap and what it should do?"
        
        mockURLSession.data = """
        {
            "content": [{"text": "\(mockResponse)"}],
            "role": "assistant"
        }
        """.data(using: .utf8)!
        
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        let task = Task {
            do {
                let response = try await provider.sendDirectMessageWithHistory(messages)
                
                if case .clarification(let message) = response {
                    XCTAssertEqual(message, mockResponse)
                    expectation.fulfill()
                } else {
                    XCTFail("Expected clarification response")
                    expectation.fulfill()
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 2.0) { _ in
            task.cancel()
        }
    }
    
    func testSendDirectMessageWithHistoryNoUserMessage() async {
        let expectation = self.expectation(description: "No user message error")
        
        // Messages with no user text (only assistant messages)
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test",
            description: "Test"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(test)",
            confidence: .high,
            explanation: "Test"
        )
        
        let messages = [
            KeyPathMessage(role: .assistant, rule: rule)
        ]
        
        let task = Task {
            do {
                _ = try await provider.sendDirectMessageWithHistory(messages)
                XCTFail("Should have thrown parsing error")
            } catch {
                XCTAssertTrue(error is AnthropicModelProvider.StructuredResponseError)
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1.0) { _ in
            task.cancel()
        }
    }
    
    func testSendDirectMessageWithHistoryEmptyMessages() async {
        let expectation = self.expectation(description: "Empty messages error")
        
        let messages: [KeyPathMessage] = []
        
        let task = Task {
            do {
                _ = try await provider.sendDirectMessageWithHistory(messages)
                XCTFail("Should have thrown parsing error")
            } catch {
                XCTAssertTrue(error is AnthropicModelProvider.StructuredResponseError)
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1.0) { _ in
            task.cancel()
        }
    }
    
    // MARK: - sendDirectMessage Tests
    
    func testSendDirectMessageRuleSuccess() async {
        let expectation = self.expectation(description: "Direct message rule success")
        
        let userInput = "Map tab to shift+tab"
        
        // Mock successful response with complex rule
        let mockResponse = """
        ```json
        {
          "visualization": {
            "behavior": {
              "type": "tapHold",
              "data": {"key": "tab", "tap": "tab", "hold": "S-tab"}
            },
            "title": "Tab Enhancement",
            "description": "Tap for tab, hold for shift+tab"
          },
          "kanata_rule": "(defalias tab (tap-hold 200 200 tab S-tab))",
          "confidence": "high",
          "explanation": "Enhanced tab key with reverse tab on hold"
        }
        ```
        """
        
        mockURLSession.data = """
        {
            "content": [{"text": "\(mockResponse)"}],
            "role": "assistant"
        }
        """.data(using: .utf8)!
        
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        let task = Task {
            do {
                let response = try await provider.sendDirectMessage(userInput)
                
                if case .rule(let rule) = response {
                    XCTAssertEqual(rule.kanataRule, "(defalias tab (tap-hold 200 200 tab S-tab))")
                    XCTAssertEqual(rule.explanation, "Enhanced tab key with reverse tab on hold")
                    XCTAssertEqual(rule.confidence, .high)
                    XCTAssertEqual(rule.visualization.title, "Tab Enhancement")
                    expectation.fulfill()
                } else {
                    XCTFail("Expected rule response")
                    expectation.fulfill()
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 2.0) { _ in
            task.cancel()
        }
    }
    
    func testSendDirectMessageClarificationSuccess() async {
        let expectation = self.expectation(description: "Direct message clarification success")
        
        let userInput = "What is 2+2?"
        let clarificationMessage = "I'm KeyPath, I help with keyboard remapping. For math questions, 2+2 equals 4!"
        
        mockURLSession.data = """
        {
            "content": [{"text": "\(clarificationMessage)"}],
            "role": "assistant"
        }
        """.data(using: .utf8)!
        
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        let task = Task {
            do {
                let response = try await provider.sendDirectMessage(userInput)
                
                if case .clarification(let message) = response {
                    XCTAssertEqual(message, clarificationMessage)
                    expectation.fulfill()
                } else {
                    XCTFail("Expected clarification response")
                    expectation.fulfill()
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 2.0) { _ in
            task.cancel()
        }
    }
    
    func testSendDirectMessageNetworkError() async {
        let expectation = self.expectation(description: "Network error handling")
        
        mockURLSession.error = URLError(.networkConnectionLost)
        
        let task = Task {
            do {
                _ = try await provider.sendDirectMessage("test input")
                XCTFail("Should have thrown network error")
            } catch {
                XCTAssertTrue(error is URLError)
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1.0) { _ in
            task.cancel()
        }
    }
    
    // MARK: - sendPhase2Message Tests
    
    func testSendPhase2MessageSuccess() async {
        let expectation = self.expectation(description: "Phase 2 message success")
        
        let remappingDescription = "Create a tap-dance for the 'a' key: single tap = 'a', double tap = 'A', triple tap = '@'"
        
        // Mock response with tap-dance rule
        let mockResponse = """
        ```json
        {
          "visualization": {
            "behavior": {
              "type": "tapDance",
              "data": {
                "key": "a",
                "actions": [
                  {"tapCount": 1, "action": "a", "description": "Single tap"},
                  {"tapCount": 2, "action": "A", "description": "Double tap"},
                  {"tapCount": 3, "action": "@", "description": "Triple tap"}
                ]
              }
            },
            "title": "Multi-function A Key",
            "description": "Tap dance for a/A/@ symbols"
          },
          "kanata_rule": "(defalias a (tap-dance 200 a A @))",
          "confidence": "high",
          "explanation": "Triple-function A key with tap dance"
        }
        ```
        """
        
        mockURLSession.data = """
        {
            "content": [{"text": "\(mockResponse)"}],
            "role": "assistant"
        }
        """.data(using: .utf8)!
        
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        let task = Task {
            do {
                let rule = try await provider.sendPhase2Message(remappingDescription)
                
                XCTAssertEqual(rule.kanataRule, "(defalias a (tap-dance 200 a A @))")
                XCTAssertEqual(rule.explanation, "Triple-function A key with tap dance")
                XCTAssertEqual(rule.confidence, .high)
                XCTAssertEqual(rule.visualization.title, "Multi-function A Key")
                
                // Verify tap-dance behavior
                if case .tapDance(let key, let actions) = rule.visualization.behavior {
                    XCTAssertEqual(key, "a")
                    XCTAssertEqual(actions.count, 3)
                    XCTAssertEqual(actions[0].tapCount, 1)
                    XCTAssertEqual(actions[1].action, "A")
                    XCTAssertEqual(actions[2].description, "Triple tap")
                } else {
                    XCTFail("Expected tap dance behavior")
                }
                
                expectation.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 2.0) { _ in
            task.cancel()
        }
    }
    
    func testSendPhase2MessageParsingFailure() async {
        let expectation = self.expectation(description: "Phase 2 parsing failure")
        
        let remappingDescription = "Create some mapping"
        
        // Mock response that can't be parsed as a rule
        let mockResponse = "I need more information to create that mapping."
        
        mockURLSession.data = """
        {
            "content": [{"text": "\(mockResponse)"}],
            "role": "assistant"
        }
        """.data(using: .utf8)!
        
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        let task = Task {
            do {
                _ = try await provider.sendPhase2Message(remappingDescription)
                XCTFail("Should have thrown parsing error")
            } catch {
                XCTAssertTrue(error is AnthropicModelProvider.StructuredResponseError)
                if let structuredError = error as? AnthropicModelProvider.StructuredResponseError {
                    XCTAssertEqual(structuredError, .parsingFailed)
                }
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 2.0) { _ in
            task.cancel()
        }
    }
    
    func testSendPhase2MessageAPIError() async {
        let expectation = self.expectation(description: "Phase 2 API error")
        
        mockURLSession.data = """
        {
            "type": "error",
            "error": {
                "type": "rate_limit_error",
                "message": "Rate limit exceeded"
            }
        }
        """.data(using: .utf8)!
        
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        let task = Task {
            do {
                _ = try await provider.sendPhase2Message("test description")
                XCTFail("Should have thrown API error")
            } catch {
                // Should propagate the underlying error from sendMessage
                expectation.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 2.0) { _ in
            task.cancel()
        }
    }
    
    // MARK: - StructuredResponseError Tests
    
    func testStructuredResponseErrorDescription() {
        let error = AnthropicModelProvider.StructuredResponseError.parsingFailed
        XCTAssertEqual(error.localizedDescription, "Failed to parse structured response from Claude")
        XCTAssertEqual(error.errorDescription, "Failed to parse structured response from Claude")
    }
    
    func testStructuredResponseErrorEquality() {
        let error1 = AnthropicModelProvider.StructuredResponseError.parsingFailed
        let error2 = AnthropicModelProvider.StructuredResponseError.parsingFailed
        
        XCTAssertEqual(error1, error2)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteWorkflowWithMultipleBehaviorTypes() async {
        let expectation = self.expectation(description: "Complete workflow test")
        expectation.expectedFulfillmentCount = 5
        
        let testCases = [
            // Simple remap
            ("Map z to y", "simpleRemap", "z", "y"),
            // Tap-hold
            ("Make space into ctrl when held", "tapHold", "spc", "ctrl"),
            // Combo
            ("Press j and k together for escape", "combo", "j+k", "esc"),
            // Sequence
            ("Type 'jk' quickly for escape", "sequence", "jk", "esc"),
            // Layer
            ("Function layer on fn key", "layer", "fn", "function")
        ]
        
        for (index, (input, behaviorType, primaryKey, expectedOutput)) in testCases.enumerated() {
            let mockResponse = createMockJSONResponse(
                behaviorType: behaviorType,
                primaryKey: primaryKey,
                output: expectedOutput,
                title: "Test \(behaviorType)",
                description: "Test \(behaviorType) mapping"
            )
            
            mockURLSession.data = """
            {
                "content": [{"text": "\(mockResponse)"}],
                "role": "assistant"
            }
            """.data(using: .utf8)!
            
            mockURLSession.response = HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            
            let task = Task {
                do {
                    let response = try await provider.sendDirectMessage(input)
                    
                    if case .rule(let rule) = response {
                        XCTAssertEqual(rule.visualization.behavior.behaviorType, getBehaviorTypeDisplayName(behaviorType))
                        XCTAssertTrue(rule.visualization.behavior.primaryKey.contains(primaryKey))
                        expectation.fulfill()
                    } else {
                        XCTFail("Expected rule response for \(input)")
                    }
                } catch {
                    XCTFail("Unexpected error for \(input): \(error)")
                }
            }
            
            // Wait a bit between requests to avoid race conditions
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            task.cancel()
        }
        
        await waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Helper Methods
    
    private func createMockJSONResponse(behaviorType: String, primaryKey: String, output: String, title: String, description: String) -> String {
        let dataSection: String
        
        switch behaviorType {
        case "simpleRemap":
            dataSection = """
            "data": {"from": "\(primaryKey)", "toKey": "\(output)"}
            """
        case "tapHold":
            dataSection = """
            "data": {"key": "\(primaryKey)", "tap": "\(primaryKey)", "hold": "\(output)"}
            """
        case "combo":
            let keys = primaryKey.split(separator: "+").map { String($0) }
            let keysJSON = keys.map { "\"\($0)\"" }.joined(separator: ", ")
            dataSection = """
            "data": {"keys": [\(keysJSON)], "result": "\(output)"}
            """
        case "sequence":
            dataSection = """
            "data": {"trigger": "\(primaryKey)", "sequence": ["\(output)"]}
            """
        case "layer":
            dataSection = """
            "data": {"key": "\(primaryKey)", "layerName": "\(output)", "mappings": {}}
            """
        default:
            dataSection = """
            "data": {"from": "\(primaryKey)", "toKey": "\(output)"}
            """
        }
        
        return """
        ```json
        {
          "visualization": {
            "behavior": {
              "type": "\(behaviorType)",
              \(dataSection)
            },
            "title": "\(title)",
            "description": "\(description)"
          },
          "kanata_rule": "(defalias \(primaryKey) \(output))",
          "confidence": "high",
          "explanation": "Test rule for \(behaviorType)"
        }
        ```
        """
    }
    
    private func getBehaviorTypeDisplayName(_ type: String) -> String {
        switch type {
        case "simpleRemap": return "Simple Remap"
        case "tapHold": return "Tap-Hold"
        case "tapDance": return "Tap Dance"
        case "sequence": return "Sequence"
        case "combo": return "Combo"
        case "layer": return "Layer"
        default: return "Unknown"
        }
    }
}