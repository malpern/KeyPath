import Foundation

/// Shared constants for Claude API integration
/// Update these when Anthropic changes their API
public enum ClaudeAPIConstants {
    /// Base URL for the Claude Messages API
    public static let messagesEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// API version header value
    public static let apiVersion = "2023-06-01"

    /// Default model for config generation and repair
    public static let defaultModel = "claude-3-5-sonnet-20241022"

    /// Maximum tokens for config generation responses
    public static let maxTokensForConfig = 4096

    /// Maximum tokens for validation requests (minimal)
    public static let maxTokensForValidation = 1

    /// Request timeout in seconds
    public static let requestTimeout: TimeInterval = 30
}
