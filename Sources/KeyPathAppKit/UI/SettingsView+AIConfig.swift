import KeyPathCore
import SwiftUI

// MARK: - AI Config Generation Settings Section

/// Settings section for AI-powered config generation
struct AIConfigGenerationSettingsSection: View {
    @State private var hasAPIKey: Bool = KeychainService.shared.hasClaudeAPIKey
    @State private var hasAPIKeyFromEnv: Bool = KeychainService.shared.hasClaudeAPIKeyFromEnvironment
    @State private var hasAPIKeyInKeychain: Bool = KeychainService.shared.hasClaudeAPIKeyInKeychain
    @State private var apiKeyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var validationError: String?
    @State private var isAddingKey: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // API Key status row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude API Key")
                        .font(.body)
                        .fontWeight(.medium)
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusButton
            }
            .accessibilityIdentifier("settings-ai-api-key-row")

            // API key input (shown when adding)
            if isAddingKey {
                apiKeyInputView
            }

            // Biometric auth toggle (only show if key is configured)
            if hasAPIKey {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Require \(BiometricAuthService.shared.biometricTypeName)")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Confirm before using API")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { BiometricAuthService.shared.isEnabled },
                        set: { BiometricAuthService.shared.isEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .accessibilityIdentifier("settings-ai-biometric-toggle")
                .accessibilityLabel("Require biometric authentication")
            }
        }
        .onAppear {
            refreshStatus()
        }
    }

    private var statusDescription: String {
        if hasAPIKeyFromEnv {
            "Using environment variable"
        } else if hasAPIKeyInKeychain {
            "Stored in Keychain"
        } else {
            "Optional for complex mappings"
        }
    }

    @ViewBuilder
    private var statusButton: some View {
        if hasAPIKeyFromEnv {
            // Environment variable - just show indicator
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else if hasAPIKeyInKeychain {
            // Has key - show remove button
            Button("Remove") {
                removeAPIKey()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("settings-ai-remove-key-button")
        } else if isAddingKey {
            // Adding key - show cancel
            Button("Cancel") {
                isAddingKey = false
                apiKeyInput = ""
                validationError = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            // No key - show add button
            Button("Add Key") {
                isAddingKey = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("settings-ai-add-key-button")
        }
    }

    @ViewBuilder
    private var apiKeyInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SecureField("sk-ant-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isValidating)
                    .accessibilityIdentifier("settings-ai-api-key-field")

                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Save") {
                        Task { await saveAPIKey() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(apiKeyInput.isEmpty)
                    .accessibilityIdentifier("settings-ai-save-key-button")
                }
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Link("Get API Key from Anthropic →", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.caption)
                .accessibilityIdentifier("settings-ai-get-key-link")
        }
        .padding(.leading, 16)
    }

    private func refreshStatus() {
        hasAPIKey = KeychainService.shared.hasClaudeAPIKey
        hasAPIKeyFromEnv = KeychainService.shared.hasClaudeAPIKeyFromEnvironment
        hasAPIKeyInKeychain = KeychainService.shared.hasClaudeAPIKeyInKeychain
    }

    private func saveAPIKey() async {
        guard !apiKeyInput.isEmpty else { return }

        isValidating = true
        validationError = nil

        let result = await APIKeyValidator.shared.validate(apiKeyInput)

        isValidating = false

        if result.isValid {
            do {
                try KeychainService.shared.storeClaudeAPIKey(apiKeyInput)
                apiKeyInput = ""
                isAddingKey = false
                refreshStatus()
            } catch {
                validationError = "Failed to save: \(error.localizedDescription)"
            }
        } else {
            validationError = result.errorMessage ?? "Invalid API key"
        }
    }

    private func removeAPIKey() {
        do {
            try KeychainService.shared.deleteClaudeAPIKey()
        } catch {
            AppLogger.shared.warn("⚠️ [SettingsView] Failed to delete API key from keychain: \(error.localizedDescription)")
        }
        refreshStatus()
    }
}

// MARK: - AI Usage History View

/// Shows the history of AI API usage and estimated costs
private struct AIUsageHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    private var costHistory: [[String: Any]] {
        AICostTracker.shared.costHistory
    }

    private var totalEstimatedCost: Double {
        AICostTracker.shared.totalEstimatedCost
    }

    private var totalTokens: (input: Int, output: Int) {
        AICostTracker.shared.totalTokens
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Usage History")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("settings-done")
                .accessibilityIdentifier("ai-usage-done-button")
            }
            .padding()

            Divider()

            if costHistory.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No AI generations yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Usage will appear here after you create complex mappings with AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("ai-usage-empty-state")
            } else {
                // Summary
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Total Estimated Cost")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("$\(String(format: "%.4f", totalEstimatedCost))")
                                .font(.title2.weight(.semibold))
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("API Calls")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(costHistory.count)")
                                .font(.title2.weight(.semibold))
                        }
                    }

                    Text("Input: \(totalTokens.input) tokens • Output: \(totalTokens.output) tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .accessibilityIdentifier("ai-usage-summary")

                // History list
                List(Array(costHistory.enumerated().reversed()), id: \.offset) { _, entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry["timestamp"] as? String ?? "Unknown")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            let inputTokens = entry["inputTokens"] as? Int ?? 0
                            let outputTokens = entry["outputTokens"] as? Int ?? 0
                            Text("\(inputTokens) input + \(outputTokens) output tokens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        let cost = entry["estimatedCost"] as? Double ?? 0
                        Text("~$\(String(format: "%.4f", cost))")
                            .font(.caption.monospacedDigit())
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer with disclaimer
            VStack(alignment: .leading, spacing: 8) {
                Text("⚠️ These are estimates based on token usage. Actual costs may vary. Check your Anthropic dashboard for exact charges.")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .italic()

                HStack {
                    Link("View Current Anthropic Pricing →", destination: URL(string: "https://www.anthropic.com/pricing")!)
                        .font(.caption2)

                    Spacer()

                    if !costHistory.isEmpty {
                        Button("Clear History") {
                            AICostTracker.shared.clearHistory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("ai-usage-clear-button")
                    }
                }
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }
}
