import SwiftUI

struct AdvancedSettingsView: View {
    @AppStorage("useStreaming") private var useStreaming = AppSettings.useStreaming
    @AppStorage("temperature") private var temperature = AppSettings.temperature
    @AppStorage("systemInstructions") private var systemInstructions = AppSettings.systemInstructions
    @AppStorage("chatProvider") private var chatProvider = AppSettings.chatProvider
    @State private var anthropicAPIKey = ""
    @State private var showAPIKey = false
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Advanced Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                    .padding(.top)

                Divider()

                // API Configuration
                VStack(alignment: .leading, spacing: 16) {
                    Text("API Configuration")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Anthropic API Key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            if showAPIKey {
                                TextField("sk-ant-api...", text: $anthropicAPIKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("sk-ant-api...", text: $anthropicAPIKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(action: { showAPIKey.toggle() }) {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .help("Your Anthropic API key. Get one at https://console.anthropic.com/")

                        if let error = saveError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.caption)
                        }

                        if anthropicAPIKey.isEmpty {
                            Label("API key required for KeyPath to work", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("API key configured")
                                    .font(.caption)
                            }
                        }

                        Link("Get an API key from Anthropic", destination: URL(string: "https://console.anthropic.com/")!)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                }

                Divider()

                // Generation Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Generation Settings")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Stream Responses", isOn: $useStreaming)

                        VStack(alignment: .leading) {
                            Text("Temperature: \(temperature, specifier: "%.2f")")
                            Slider(value: $temperature, in: 0.0...2.0, step: 0.1)
                            Text("Higher values make output more creative but less focused")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("System Instructions")
                                .font(.subheadline)
                            TextEditor(text: $systemInstructions)
                                .frame(minHeight: 100)
                                .font(.body)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Load API key from Keychain if available
            if let keychainKey = KeychainManager.shared.apiKey, !keychainKey.isEmpty {
                anthropicAPIKey = keychainKey
            }
        }
        .onChange(of: anthropicAPIKey) { _, newValue in
            // Save to Keychain when API key changes
            if !newValue.isEmpty {
                do {
                    try KeychainManager.shared.setAPIKey(newValue)
                    saveError = nil
                } catch {
                    saveError = "Failed to save API key securely: \(error.localizedDescription)"
                }
            }
        }
    }
}