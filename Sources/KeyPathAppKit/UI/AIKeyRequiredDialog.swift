import KeyPathCore
import SwiftUI

/// Dialog shown when a user tries to use AI config generation without an API key
/// Explains the feature, costs, and allows entering an API key
struct AIKeyRequiredDialog: View {
    /// Callback when API key is successfully saved
    let onSave: (String) -> Void

    /// Callback when user dismisses without saving
    let onDismiss: () -> Void

    /// Callback when user chooses to skip AI (use basic generation)
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var validationError: String?
    @State private var dontShowAgain: Bool = false

    /// UserDefaults key to track if user dismissed dialog
    static let dismissedKey = "KeyPath.AI.KeyDialogDismissed"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Content
            ScrollView {
                contentSection
            }

            Divider()

            // Footer with buttons
            footerSection
        }
        .frame(width: 480, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .topTrailing) {
            Button(action: handleDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityIdentifier("ai-key-dialog-close-button")
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("AI Config Generation")
                .font(.title2.weight(.semibold))

            Text("Create complex keyboard mappings with AI")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ai-key-dialog-header")
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // What is this?
            featureExplanation

            // Cost information
            costInformation

            // API Key input
            apiKeyInputSection

            // Security note
            securityNote
        }
        .padding(24)
    }

    private var featureExplanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What is this?", systemImage: "questionmark.circle.fill")
                .font(.headline)

            Text("KeyPath can use Claude AI to generate complex Kanata configurations for:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                bulletPoint("Key sequences (e.g., type 'hello' with one key)")
                bulletPoint("Chord combinations (e.g., press A+B together)")
                bulletPoint("Macros and complex actions")
                bulletPoint("App-specific shortcuts")
            }
            .padding(.leading, 24)

            Text("Simple single-key remaps work without AI.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .accessibilityIdentifier("ai-key-dialog-feature-section")
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var costInformation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cost Information", systemImage: "dollarsign.circle.fill")
                .font(.headline)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("• Each complex mapping costs approximately $0.01-0.03")
                Text("• Simple mappings are always free (no API call)")
                Text("• Costs vary based on Anthropic's pricing")
                Text("• Check your Anthropic dashboard for exact charges")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading, 24)

            Link("View Current Anthropic Pricing →", destination: URL(string: "https://www.anthropic.com/pricing")!)
                .font(.caption)
                .padding(.leading, 24)
                .accessibilityIdentifier("ai-key-dialog-pricing-link")
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .accessibilityIdentifier("ai-key-dialog-cost-section")
    }

    private var apiKeyInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Enter API Key", systemImage: "key.fill")
                .font(.headline)

            HStack {
                SecureField("sk-ant-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isValidating)
                    .accessibilityIdentifier("ai-key-dialog-api-key-field")

                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("ai-key-dialog-error-message")
            }

            HStack {
                Text("Don't have an API key?")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link("Get one from Anthropic →", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
                    .accessibilityIdentifier("ai-key-dialog-get-key-link")
            }
        }
        .accessibilityIdentifier("ai-key-dialog-input-section")
    }

    private var securityNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your API key is stored securely")
                    .font(.caption.weight(.medium))
                Text("Saved in macOS Keychain, never sent anywhere except Anthropic")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .accessibilityIdentifier("ai-key-dialog-security-note")
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle("Don't show this again", isOn: $dontShowAgain)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .accessibilityIdentifier("ai-key-dialog-dont-show-toggle")

                Spacer()
            }

            HStack(spacing: 12) {
                Button("Skip (Use Basic)") {
                    handleSkip()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ai-key-dialog-skip-button")

                Spacer()

                Button("Cancel") {
                    handleDismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ai-key-dialog-cancel-button")

                Button("Save & Continue") {
                    Task {
                        await saveAPIKey()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.isEmpty || isValidating)
                .accessibilityIdentifier("ai-key-dialog-save-button")
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    private func saveAPIKey() async {
        assert(!apiKeyInput.isEmpty, "Should not call saveAPIKey with empty input")

        isValidating = true
        validationError = nil

        // Validate the API key
        let validator = APIKeyValidator.shared
        let result = await validator.validate(apiKeyInput)

        isValidating = false

        if result.isValid {
            // Store in keychain
            do {
                try KeychainService.shared.storeClaudeAPIKey(apiKeyInput)

                if dontShowAgain {
                    UserDefaults.standard.set(true, forKey: Self.dismissedKey)
                }

                AppLogger.shared.log("✅ [AIKeyDialog] API key saved successfully")
                onSave(apiKeyInput)
                dismiss()
            } catch {
                validationError = "Failed to save API key: \(error.localizedDescription)"
                AppLogger.shared.log("❌ [AIKeyDialog] Failed to save API key: \(error)")
            }
        } else {
            validationError = result.errorMessage ?? "Invalid API key"
            AppLogger.shared.log("❌ [AIKeyDialog] API key validation failed: \(result.errorMessage ?? "unknown")")
        }
    }

    private func handleDismiss() {
        if dontShowAgain {
            UserDefaults.standard.set(true, forKey: Self.dismissedKey)
        }
        onDismiss()
        dismiss()
    }

    private func handleSkip() {
        if dontShowAgain {
            UserDefaults.standard.set(true, forKey: Self.dismissedKey)
        }
        onSkip()
        dismiss()
    }

    // MARK: - Static Helpers

    /// Check if user has previously dismissed the dialog
    static var hasBeenDismissed: Bool {
        UserDefaults.standard.bool(forKey: dismissedKey)
    }

    /// Reset the dismissed state (for testing or settings)
    static func resetDismissedState() {
        UserDefaults.standard.removeObject(forKey: dismissedKey)
    }

    /// Check if we should show the dialog for a complex mapping attempt
    /// Returns true if:
    /// - User has no API key
    /// - User hasn't dismissed the dialog
    static func shouldShow() -> Bool {
        !KeychainService.shared.hasClaudeAPIKey && !hasBeenDismissed
    }
}

// MARK: - Preview

#Preview {
    AIKeyRequiredDialog(
        onSave: { key in print("Saved: \(key.prefix(10))...") },
        onDismiss: { print("Dismissed") },
        onSkip: { print("Skipped") }
    )
}
