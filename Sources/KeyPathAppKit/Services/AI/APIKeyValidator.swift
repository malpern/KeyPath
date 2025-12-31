import Foundation
import KeyPathCore

/// Validates Anthropic API keys by making a minimal test request
/// This service verifies that an API key is valid before storing it in Keychain
public actor APIKeyValidator {
    /// Shared instance for convenience
    public static let shared = APIKeyValidator()

    private let endpoint = ClaudeAPIConstants.messagesEndpoint
    private let apiVersion = ClaudeAPIConstants.apiVersion
    private let model = ClaudeAPIConstants.defaultModel

    /// Validation result with detailed information
    public struct ValidationResult: Sendable {
        public let isValid: Bool
        public let errorMessage: String?
        public let statusCode: Int?

        public static func valid() -> ValidationResult {
            ValidationResult(isValid: true, errorMessage: nil, statusCode: 200)
        }

        public static func invalid(message: String, statusCode: Int? = nil) -> ValidationResult {
            ValidationResult(isValid: false, errorMessage: message, statusCode: statusCode)
        }
    }

    /// Error types for validation failures
    public enum ValidationError: Error, LocalizedError {
        case invalidKey
        case networkError(String)
        case apiError(statusCode: Int, message: String)
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .invalidKey:
                "Invalid API key. Please check your key and try again."
            case let .networkError(message):
                "Network error: \(message)"
            case let .apiError(statusCode, message):
                "API error (\(statusCode)): \(message)"
            case .invalidResponse:
                "Invalid response from API"
            }
        }
    }

    /// Validate an API key by making a minimal test request
    /// - Parameter key: The Anthropic API key to validate
    /// - Returns: ValidationResult indicating success or failure with details
    public func validate(_ key: String) async -> ValidationResult {
        assert(!key.isEmpty, "API key cannot be empty")

        // Basic format check before making network request
        guard key.hasPrefix("sk-ant-") else {
            AppLogger.shared.log("❌ [APIKeyValidator] Key doesn't start with 'sk-ant-'")
            return .invalid(message: "API key should start with 'sk-ant-'")
        }

        guard key.count > 20 else {
            AppLogger.shared.log("❌ [APIKeyValidator] Key too short")
            return .invalid(message: "API key appears to be incomplete")
        }

        AppLogger.shared.log("🔑 [APIKeyValidator] Validating API key...")

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue(key, forHTTPHeaderField: "x-api-key")
            request.addValue(apiVersion, forHTTPHeaderField: "anthropic-version")
            request.timeoutInterval = 30

            // Minimal test request - just check auth, uses minimal tokens
            let requestBody: [String: Any] = [
                "model": model,
                "max_tokens": 1, // Absolute minimum to validate auth
                "messages": [
                    [
                        "role": "user",
                        "content": "Hi" // Minimal content
                    ]
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.shared.log("❌ [APIKeyValidator] Invalid response type")
                return .invalid(message: "Invalid response from API")
            }

            // Check status code
            switch httpResponse.statusCode {
            case 200 ... 299:
                AppLogger.shared.log("✅ [APIKeyValidator] API key is valid")
                return .valid()

            case 401:
                AppLogger.shared.log("❌ [APIKeyValidator] Invalid API key (401)")
                return .invalid(message: "Invalid API key. Please check your key and try again.", statusCode: 401)

            case 403:
                AppLogger.shared.log("❌ [APIKeyValidator] API key lacks permissions (403)")
                return .invalid(message: "API key doesn't have required permissions.", statusCode: 403)

            case 429:
                // Rate limited but key is valid
                AppLogger.shared.log("✅ [APIKeyValidator] API key valid (rate limited)")
                return .valid()

            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                AppLogger.shared.log("❌ [APIKeyValidator] API error: \(httpResponse.statusCode)")
                return .invalid(message: "API error: \(errorMessage)", statusCode: httpResponse.statusCode)
            }

        } catch let error as URLError {
            AppLogger.shared.log("❌ [APIKeyValidator] Network error: \(error.localizedDescription)")
            return .invalid(message: "Network error: \(error.localizedDescription)")
        } catch {
            AppLogger.shared.log("❌ [APIKeyValidator] Unexpected error: \(error)")
            return .invalid(message: "Unexpected error: \(error.localizedDescription)")
        }
    }

    /// Validate and throw on failure (convenience method)
    /// - Parameter key: The Anthropic API key to validate
    /// - Throws: ValidationError if the key is invalid
    public func validateOrThrow(_ key: String) async throws {
        let result = await validate(key)

        guard result.isValid else {
            if let statusCode = result.statusCode, statusCode == 401 {
                throw ValidationError.invalidKey
            } else if let message = result.errorMessage {
                throw ValidationError.apiError(statusCode: result.statusCode ?? 0, message: message)
            } else {
                throw ValidationError.invalidResponse
            }
        }
    }
}
