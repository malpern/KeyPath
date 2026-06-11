import Foundation
import KeyPathCore

/// Implementation of ConfigRepairService using Anthropic's Claude API
public actor AnthropicConfigRepairService: ConfigRepairService {
    private let endpoint: URL
    private let model: String
    private let version: String

    public init(
        endpoint: URL = ClaudeAPIConstants.messagesEndpoint,
        model: String = ClaudeAPIConstants.defaultModel,
        version: String = ClaudeAPIConstants.apiVersion
    ) {
        self.endpoint = endpoint
        self.model = model
        self.version = version
    }

    public func repairConfig(config: String, errors: [String], mappings: [KeyMapping]) async throws -> String {
        // Mirror the user's command-actions policy: repair must not (re)enable cmd
        // execution for users who have it off, nor strip it for grandfathered users.
        let defcfgInstruction = KanataCommandActionsPolicy.isEnabled()
            ? "Includes defcfg with process-unmapped-keys no and danger-enable-cmd yes"
            : "Includes defcfg with process-unmapped-keys no, and does NOT include danger-enable-cmd or any (cmd ...) actions"
        let prompt = """
        The following Kanata keyboard configuration file is invalid and needs to be repaired:

        INVALID CONFIG:
        ```
        \(config)
        ```

        VALIDATION ERRORS:
        \(errors.joined(separator: "\n"))

        INTENDED KEY MAPPINGS:
        \(mappings.map { "\($0.input) -> \($0.action.kanataOutput)" }.joined(separator: "\n"))

        Please generate a corrected Kanata configuration that:
        1. Fixes all validation errors
        2. Preserves the intended key mappings
        3. Uses proper Kanata syntax
        4. \(defcfgInstruction)
        5. Has proper defsrc and deflayer sections

        Return ONLY the corrected configuration file content, no explanations.
        """

        return try await callClaudeAPI(prompt: prompt)
    }

    private func callClaudeAPI(prompt: String) async throws -> String {
        // Get API key using KeychainService (static method for non-MainActor access)
        guard let apiKey = KeychainService.getClaudeAPIKeyStatic() else {
            throw NSError(
                domain: "ClaudeAPI", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "AI repair requires an API key. Add one in Settings → General → AI Configuration."
                ]
            )
        }

        // Biometric authentication before expensive API call
        let authResult = await BiometricAuthService.shared.authenticate(
            reason: BiometricAuthService.defaultAuthReason
        )

        switch authResult {
        case .cancelled:
            throw NSError(
                domain: "ClaudeAPI", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Authentication cancelled"]
            )
        case let .failed(errorMessage):
            // Fail-closed: an unexpected auth error must not bypass the consent gate
            // for a paid API call. Legit no-biometrics cases already route to password.
            AppLogger.shared.log("⚠️ [ConfigRepair] Auth failed: \(errorMessage), aborting")
            throw NSError(
                domain: "ClaudeAPI", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Authentication failed: \(errorMessage)"]
            )
        case .authenticated, .notRequired:
            break
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue(version, forHTTPHeaderField: "anthropic-version")

        let requestBody: [String: Any] = [
            "model": model,
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

        // Extract and log usage for cost tracking
        if let usage = jsonResponse["usage"] as? [String: Any],
           let inputTokens = usage["input_tokens"] as? Int,
           let outputTokens = usage["output_tokens"] as? Int
        {
            await AICostTracker.shared.trackUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                source: .configRepair,
                logPrefix: "ConfigRepair"
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
