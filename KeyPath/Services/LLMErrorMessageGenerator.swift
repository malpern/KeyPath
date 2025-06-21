import Foundation

// ⚠️ ARCHITECTURE COMPLIANT: LLM-First Error Handling
// This service uses LLM intelligence to generate contextual, helpful error messages
// instead of hardcoded error pattern matching.
// See ARCHITECTURE.md for LLM-first guidelines.

/// Generates intelligent, contextual error messages using LLM analysis
class LLMErrorMessageGenerator {
    private let llmProvider: AnthropicModelProvider?
    private var errorMessageCache: [String: String] = [:]
    
    init(llmProvider: AnthropicModelProvider? = nil) {
        self.llmProvider = llmProvider
    }
    
    /// Generates a user-friendly error message using LLM intelligence
    /// Falls back to sensible defaults if LLM is unavailable
    func generateUserFriendlyErrorMessage(
        from error: Error,
        context: ErrorContext? = nil
    ) async -> String {
        let errorKey = "\(error.localizedDescription)_\(context?.description ?? "none")"
        
        // Check cache first
        if let cachedMessage = errorMessageCache[errorKey] {
            return cachedMessage
        }
        
        // Try LLM-powered error analysis first
        if let llmMessage = await generateLLMErrorMessage(error: error, context: context) {
            errorMessageCache[errorKey] = llmMessage
            return llmMessage
        }
        
        // Fallback to basic pattern matching for critical errors
        return generateFallbackErrorMessage(from: error)
    }
    
    // MARK: - LLM-Powered Error Analysis
    
    private func generateLLMErrorMessage(
        error: Error,
        context: ErrorContext?
    ) async -> String? {
        guard let llmProvider = llmProvider else { return nil }
        
        let prompt = createErrorAnalysisPrompt(error: error, context: context)
        
        do {
            let response = try await llmProvider.sendMessage(prompt)
            
            // Clean up the response to get just the error message
            let cleanedResponse = response
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```", with: "")
                .replacingOccurrences(of: "**", with: "")
            
            return cleanedResponse.isEmpty ? nil : cleanedResponse
        } catch {
            // If LLM fails, we'll fall back to basic patterns
            return nil
        }
    }
    
    private func createErrorAnalysisPrompt(error: Error, context: ErrorContext?) -> String {
        let contextInfo = context?.description ?? "General KeyPath usage"
        
        return """
        You are helping a KeyPath user understand an error. Generate a helpful, actionable error message.
        
        CONTEXT: \(contextInfo)
        ERROR: \(error.localizedDescription)
        
        Requirements:
        1. Be empathetic and helpful, not technical
        2. Provide specific, actionable steps to resolve the issue
        3. Use Mac-friendly terminology (⌘ for Command, etc.)
        4. Keep it concise but complete
        5. If it's an API/network issue, mention checking Settings
        6. If it's a keyboard-related issue, suggest alternative phrasings
        
        Common error types and approaches:
        - API key issues → Guide to Settings and Anthropic console
        - Network errors → Check connection and API status
        - Rate limits → Wait and consider plan upgrade
        - Invalid requests → Suggest rephrasing the keyboard mapping
        - Kanata validation → Explain the specific issue and how to fix it
        
        Generate ONLY the user-friendly error message, no extra text or formatting:
        """
    }
    
    // MARK: - Fallback Error Handling
    
    private func generateFallbackErrorMessage(from error: Error) -> String {
        let errorString = error.localizedDescription.lowercased()
        
        // Essential error patterns that must work even without LLM
        if errorString.contains("x-api-key") || errorString.contains("authentication") {
            return """
            API Key Missing or Invalid
            
            To use KeyPath, you need to add your Anthropic API key:
            
            1. Open Settings (⌘,)
            2. Enter your Anthropic API key
            3. If you don't have one, get it at:
               https://console.anthropic.com/
            
            Your API key should start with 'sk-ant-api...'
            """
        } else if errorString.contains("network") || errorString.contains("connection") {
            return """
            Network Connection Error
            
            Please check your internet connection and try again.
            If the problem persists, the Anthropic API may be temporarily unavailable.
            """
        } else if errorString.contains("rate limit") {
            return """
            Rate Limit Exceeded
            
            You've made too many requests. Please wait a moment and try again.
            Consider upgrading your Anthropic plan for higher limits.
            """
        } else {
            return """
            An error occurred while processing your request.
            
            Error details: \(error.localizedDescription)
            
            Try rephrasing your keyboard remapping description, or check:
            - Your API key in Settings (⌘,)
            - Your internet connection
            - The Anthropic API status
            """
        }
    }
}

// MARK: - Error Context

/// Provides context about where/when an error occurred to help generate better messages
struct ErrorContext {
    let operation: String
    let userInput: String?
    let additionalInfo: [String: String]
    
    var description: String {
        var parts = ["Operation: \(operation)"]
        
        if let input = userInput {
            parts.append("User input: '\(input)'")
        }
        
        for (key, value) in additionalInfo {
            parts.append("\(key): \(value)")
        }
        
        return parts.joined(separator: ", ")
    }
    
    init(operation: String, userInput: String? = nil, additionalInfo: [String: String] = [:]) {
        self.operation = operation
        self.userInput = userInput
        self.additionalInfo = additionalInfo
    }
}
