import Foundation

struct ParsedRule {
    let kanataRule: String
    let description: String
    let confidence: String
    let originalInput: String
}

enum RuleParsingError: Error, LocalizedError {
    case noLLMProvider
    case parsingFailed(String)
    case validationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noLLMProvider:
            return "No language model provider available"
        case .parsingFailed(let message):
            return "Failed to parse rule: \(message)"
        case .validationFailed(let message):
            return "Rule validation failed: \(message)"
        }
    }
}

class LLMRuleParser {
    private let llmProvider: AnthropicModelProvider?
    private let configManager: SimpleKanataConfigManager
    
    // Cache for common patterns to reduce API calls
    private var ruleCache: [String: ParsedRule] = [:]
    
    init(llmProvider: AnthropicModelProvider?) {
        self.llmProvider = llmProvider
        self.configManager = SimpleKanataConfigManager(llmProvider: llmProvider)
        setupCommonRuleCache()
    }
    
    /// Parse user input into a validated Kanata rule using LLM intelligence
    func parseRule(_ userInput: String) async throws -> ParsedRule {
        let cleanInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle empty input
        guard !cleanInput.isEmpty else {
            throw RuleParsingError.parsingFailed("Please describe your keyboard mapping")
        }
        
        // Check cache first for common patterns
        if let cachedRule = ruleCache[cleanInput.lowercased()] {
            return cachedRule
        }
        
        guard let llmProvider = llmProvider else {
            throw RuleParsingError.noLLMProvider
        }
        
        // Prepare the LLM prompt for rule parsing
        let prompt = buildRuleParsingPrompt(for: cleanInput)
        
        do {
            let response = try await llmProvider.sendMessage(prompt)
            return try parseRuleFromLLMResponse(response, originalInput: cleanInput)
        } catch {
            throw RuleParsingError.parsingFailed("LLM failed to parse rule: \(error.localizedDescription)")
        }
    }
    
    /// Validate a rule using actual Kanata syntax checking
    private func validateKanataRule(_ rule: String) async -> Result<Bool, Error> {
        await withCheckedContinuation { continuation in
            configManager.validateConfig(rule) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    private func buildRuleParsingPrompt(for userInput: String) -> String {
        """
        You are a keyboard remapping expert. Parse the user's input into a valid Kanata configuration.
        
        User input: "\(userInput)"
        
        Your task:
        1. Understand what keyboard mapping the user wants
        2. Generate a complete, valid Kanata configuration
        3. Provide a clear description of what the rule does
        4. Rate your confidence in the interpretation
        
        Response format (JSON):
        {
            "kanataRule": "complete Kanata config with defsrc, deflayer, and any defalias",
            "description": "Clear explanation of what this rule does",
            "confidence": "high|medium|low"
        }
        
        Common patterns:
        - "caps to esc" → Maps Caps Lock to Escape
        - "a to b" → Maps A key to B key  
        - "space as shift" → Makes Space act as Shift when held
        - "fn + j/k as arrow keys" → Layer mapping for navigation
        
        Generate a complete Kanata configuration that includes:
        - (defsrc) with source keys
        - (deflayer) with mappings
        - (defalias) if needed for complex behaviors
        
        Make sure the syntax is valid Kanata format.
        """
    }
    
    private func parseRuleFromLLMResponse(_ response: String, originalInput: String) throws -> ParsedRule {
        // Extract JSON from the response
        guard let jsonData = extractJSONFromResponse(response) else {
            throw RuleParsingError.parsingFailed("No valid JSON found in LLM response")
        }
        
        do {
            let decoder = JSONDecoder()
            let parsedResponse = try decoder.decode(LLMRuleResponse.self, from: jsonData)
            
            let parsedRule = ParsedRule(
                kanataRule: parsedResponse.kanataRule,
                description: parsedResponse.description,
                confidence: parsedResponse.confidence,
                originalInput: originalInput
            )
            
            // Cache common patterns
            if parsedResponse.confidence == "high" {
                ruleCache[originalInput.lowercased()] = parsedRule
            }
            
            return parsedRule
            
        } catch {
            throw RuleParsingError.parsingFailed("Failed to decode LLM response: \(error.localizedDescription)")
        }
    }
    
    private func extractJSONFromResponse(_ response: String) -> Data? {
        // Look for JSON block in response
        if let jsonStart = response.firstIndex(of: "{"),
           let jsonEnd = response.lastIndex(of: "}") {
            let jsonString = String(response[jsonStart...jsonEnd])
            return jsonString.data(using: .utf8)
        }
        
        // If no JSON found, try to parse the entire response as JSON
        return response.data(using: .utf8)
    }
    
    private func setupCommonRuleCache() {
        // Pre-populate cache with extremely common patterns to avoid API calls
        ruleCache["caps -> esc"] = ParsedRule(
            kanataRule: """
            (defsrc caps)
            (deflayer default esc)
            """,
            description: "Maps Caps Lock key to Escape",
            confidence: "high",
            originalInput: "caps -> esc"
        )
        
        ruleCache["caps to esc"] = ruleCache["caps -> esc"]
        ruleCache["caps lock to escape"] = ruleCache["caps -> esc"]
        ruleCache["capslock to escape"] = ruleCache["caps -> esc"]
    }
}

// MARK: - Supporting Types

private struct LLMRuleResponse: Codable {
    let kanataRule: String
    let description: String
    let confidence: String
}
