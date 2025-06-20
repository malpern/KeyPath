import SwiftUI

struct APIKeyStep: View {
    @Binding var tempAPIKey: String
    @Binding var showAPIKey: Bool
    @State private var isValidating = false
    @State private var savedAPIKey = ""
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var saveSuccess = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Connect to Claude AI")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 16) {
                Text("KeyPath uses Claude AI to translate your natural language into keyboard remapping rules.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Anthropic API Key:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text("🔐 Your API key will be securely stored in macOS Keychain")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .padding(.bottom, 4)

                    HStack {
                        if showAPIKey {
                            TextField("sk-ant-api...", text: $tempAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-api...", text: $tempAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 400)

                    HStack(spacing: 4) {
                        Text("Don't have an API key?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Link("Get one at console.anthropic.com",
                             destination: URL(string: "https://console.anthropic.com/")!)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 40)

                if !tempAPIKey.isEmpty && !saveSuccess {
                    Button(action: {
                        isSaving = true
                        saveError = nil

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            do {
                                try KeychainManager.shared.setAPIKey(tempAPIKey)
                                savedAPIKey = tempAPIKey
                                saveSuccess = true
                                SoundManager.shared.playSound(.success)
                            } catch {
                                saveError = "Failed to save API key: \(error.localizedDescription)"
                            }
                            isSaving = false
                        }
                    }) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Saving...")
                            } else {
                                Text("Save to Keychain")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .disabled(isSaving)

                    if !saveSuccess {
                        Text("macOS will ask for permission to access Keychain")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 4)
                    }
                }

                if saveSuccess {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API Key Saved Successfully!")
                                .fontWeight(.medium)
                        }
                        .font(.callout)
                        .foregroundColor(.green)

                        Text("Your API key is now securely stored in macOS Keychain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 40)
                }

                if let error = saveError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal, 40)
                }

                Text("You can skip this step and add your API key later in Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .onAppear {
            // Check for existing API key from Keychain
            if let keychainKey = KeychainManager.shared.apiKey, !keychainKey.isEmpty {
                tempAPIKey = keychainKey
                savedAPIKey = keychainKey
            }
        }
    }
}