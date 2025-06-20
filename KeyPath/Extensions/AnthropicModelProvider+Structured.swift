import Foundation

enum DirectResponse {
    case rule(KanataRule)
    case clarification(String)
}

extension AnthropicModelProvider {
    func sendDirectMessageWithHistory(_ messages: [KeyPathMessage]) async throws -> DirectResponse {
        // Get the last user message
        guard let lastUserMessage = messages.last(where: { $0.role == .user }),
              case .text(let userText) = lastUserMessage.type else {
            throw StructuredResponseError.parsingFailed
        }

        // Create a modified version of messages with the prompt as system instruction
        var contextMessages = messages
        
        // Replace the last user message with the prompt-enhanced version
        if let lastIndex = contextMessages.lastIndex(where: { $0.role == .user }) {
            let enhancedPrompt = ClaudePromptTemplates.directGenerationPrompt.replacingOccurrences(of: "{USER_INPUT}", with: userText)
            contextMessages[lastIndex] = KeyPathMessage(role: .user, text: enhancedPrompt)
        }
        
        // Use conversation method to include full context
        let response = try await sendConversation(contextMessages)

        // Debug: Always log the response to understand what we're getting
        print("🔧 DEBUG: Claude response received:")
        print("Response: \(response)")
        print("🔧 DEBUG: End of response")

        // Try to parse as KanataRule first
        if let kanataRule = KanataRule.parse(from: response) {
            print("🔧 DEBUG: Successfully parsed KanataRule")
            let validatedRule = try await validateAndFixRule(kanataRule, userInput: userText, maxRetries: 3)
            print("🔧 DEBUG: Validation completed successfully")
            return .rule(validatedRule)
        } else {
            print("🔧 DEBUG: Failed to parse as KanataRule, treating as clarification")
            // Otherwise it's a clarifying question or educational response
            return .clarification(response)
        }
    }

    func sendDirectMessage(_ userInput: String) async throws -> DirectResponse {
        let prompt = ClaudePromptTemplates.directGenerationPrompt.replacingOccurrences(of: "{USER_INPUT}", with: userInput)

        let response = try await sendMessage(prompt)

        // Debug: Always log the response to understand what we're getting
        print("🔧 DEBUG: Claude response received (direct):")
        print("Response: \(response)")
        print("🔧 DEBUG: End of response")

        // Try to parse as KanataRule first
        if let kanataRule = KanataRule.parse(from: response) {
            print("🔧 DEBUG: Successfully parsed KanataRule (direct)")
            let validatedRule = try await validateAndFixRule(kanataRule, userInput: userInput, maxRetries: 3)
            print("🔧 DEBUG: Validation completed successfully (direct)")
            return .rule(validatedRule)
        } else {
            print("🔧 DEBUG: Failed to parse as KanataRule (direct), treating as clarification")
            // Otherwise it's a clarifying question
            return .clarification(response)
        }
    }

    func sendPhase2Message(_ remappingDescription: String) async throws -> KanataRule {
        let prompt = ClaudePromptTemplates.formatPhase2Prompt(remappingDescription: remappingDescription)

        let response = try await sendMessage(prompt)

        guard let kanataRule = KanataRule.parse(from: response) else {
            throw StructuredResponseError.parsingFailed
        }

        return kanataRule
    }

    enum StructuredResponseError: Error, LocalizedError {
        case parsingFailed
        case validationFailed(String)

        var errorDescription: String? {
            switch self {
            case .parsingFailed:
                return "Failed to parse structured response from Claude"
            case .validationFailed(let message):
                return "Rule validation failed: \(message)"
            }
        }
    }
    
    private func validateAndFixRule(_ rule: KanataRule, userInput: String, maxRetries: Int) async throws -> KanataRule {
        var currentRule = rule
        var retryCount = 0
        
        while retryCount < maxRetries {
            // Validate the complete config using SimpleKanataConfigManager
            let configManager = SimpleKanataConfigManager()
            let validationResult = await withCheckedContinuation { continuation in
                configManager.validateConfig(currentRule.completeKanataConfig) { result in
                    continuation.resume(returning: result)
                }
            }
            
            switch validationResult {
            case .success:
                // Rule is valid, return it
                return currentRule
                
            case .failure(let error):
                retryCount += 1
                
                if retryCount >= maxRetries {
                    throw StructuredResponseError.validationFailed("Failed to generate valid Kanata syntax after \(maxRetries) attempts. Last error: \(error.localizedDescription)")
                }
                
                // Ask LLM to fix the invalid rule
                let fixPrompt = """
                The Kanata configuration you generated is invalid. Here's the error:
                
                Error: \(error.localizedDescription)
                
                Invalid configuration:
                \(currentRule.completeKanataConfig)
                
                Please fix this configuration. Remember to generate a complete, self-contained Kanata configuration block that includes:
                - (defsrc) section with the source key(s)
                - (deflayer) section with the target mapping
                - Valid Kanata syntax
                
                User's original request: "\(userInput)"
                
                Please generate a corrected version following the same JSON format.
                """
                
                let fixResponse = try await sendMessage(fixPrompt)
                
                // Parse the fixed rule
                guard let fixedRule = KanataRule.parse(from: fixResponse) else {
                    throw StructuredResponseError.parsingFailed
                }
                
                currentRule = fixedRule
            }
        }
        
        throw StructuredResponseError.validationFailed("Failed to generate valid rule after \(maxRetries) attempts")
    }
}
