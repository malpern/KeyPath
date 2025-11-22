import Foundation
import KeyPathCore

/// Implementation of ConfigRepairService using Anthropic's Claude API
public actor AnthropicConfigRepairService: ConfigRepairService {
    public init() {}

    public func repairConfig(config: String, errors: [String], mappings: [KeyMapping]) async throws -> String {
        let prompt = """
        The following Kanata keyboard configuration file is invalid and needs to be repaired:

        INVALID CONFIG:
        ```
        \(config)
        ```

        VALIDATION ERRORS:
        \(errors.joined(separator: "\n"))

        INTENDED KEY MAPPINGS:
        \(mappings.map { "\($0.input) -> \($0.output)" }.joined(separator: "\n"))

        Please generate a corrected Kanata configuration that:
        1. Fixes all validation errors
        2. Preserves the intended key mappings
        3. Uses proper Kanata syntax
        4. Includes defcfg with process-unmapped-keys no and danger-enable-cmd yes
        5. Has proper defsrc and deflayer sections

        Return ONLY the corrected configuration file content, no explanations.
        """

        return try await callClaudeAPI(prompt: prompt)
    }

    private func callClaudeAPI(prompt: String) async throws -> String {
        // Check for API key in environment or keychain
        guard let apiKey = getClaudeAPIKey() else {
            throw NSError(
                domain: "ClaudeAPI", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Claude API key not found. Set ANTHROPIC_API_KEY environment variable or store in Keychain."
                ]
            )
        }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw NSError(
                domain: "ClaudeAPI", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Claude API URL"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let requestBody: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "ClaudeAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
            )
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "ClaudeAPI", code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "API request failed (\(httpResponse.statusCode)): \(errorMessage)"
                ]
            )
        }

        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = jsonResponse["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String
        else {
            throw NSError(
                domain: "ClaudeAPI", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse Claude API response"]
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get Claude API key from environment variable or keychain
    private func getClaudeAPIKey() -> String? {
        // First try environment variable
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            return envKey
        }

        // Try keychain (using the same pattern as other keychain access in the app)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "KeyPath",
            kSecAttrAccount as String: "claude-api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return key
    }
}
