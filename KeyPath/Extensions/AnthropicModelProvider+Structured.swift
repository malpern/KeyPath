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

        // Use the direct generation prompt
        let prompt = ClaudePromptTemplates.directGenerationPrompt.replacingOccurrences(of: "{USER_INPUT}", with: userText)
        let response = try await sendMessage(prompt)

        // Try to parse as KanataRule first
        if let kanataRule = KanataRule.parse(from: response) {
            return .rule(kanataRule)
        } else {
            // Otherwise it's a clarifying question
            return .clarification(response)
        }
    }

    func sendDirectMessage(_ userInput: String) async throws -> DirectResponse {
        let prompt = ClaudePromptTemplates.directGenerationPrompt.replacingOccurrences(of: "{USER_INPUT}", with: userInput)

        let response = try await sendMessage(prompt)

        // Try to parse as KanataRule first
        if let kanataRule = KanataRule.parse(from: response) {
            return .rule(kanataRule)
        } else {
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

        var errorDescription: String? {
            switch self {
            case .parsingFailed:
                return "Failed to parse structured response from Claude"
            }
        }
    }
}
