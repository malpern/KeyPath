//
//  SettingsView.swift
//  KeyPath
//
//  Created by Pallav Agarwal on 6/9/25.
//

import SwiftUI

/// App-wide settings stored in UserDefaults
enum ChatProvider: String, CaseIterable, Identifiable {
    case apple = "Apple"
    case anthropic = "Anthropic"
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .apple:
            return "KeyPath"
        case .anthropic:
            return "Anthropic Sonnet Chat"
        }
    }
}

enum AppSettings {
    @AppStorage("useStreaming") static var useStreaming: Bool = true
    @AppStorage("temperature") static var temperature: Double = 0.7
    @AppStorage("systemInstructions") static var systemInstructions: String = "You are a helpful assistant."
    @AppStorage("chatProvider") static var chatProvider: ChatProvider = .anthropic
}

/// Settings screen for configuring AI behavior
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var onDismiss: (() -> Void)?
    
    @AppStorage("useStreaming") private var useStreaming = AppSettings.useStreaming
    @AppStorage("temperature") private var temperature = AppSettings.temperature
    @AppStorage("systemInstructions") private var systemInstructions = AppSettings.systemInstructions
    @AppStorage("chatProvider") private var chatProvider = AppSettings.chatProvider
    @State private var anthropicAPIKey = ""
    @State private var showAPIKey = false
    @State private var usingOverride = false
    @State private var saveError: String? = nil
    
    private var environmentAPIKey: String? {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }
    
    private var effectiveAPIKey: String {
        if !anthropicAPIKey.isEmpty {
            return anthropicAPIKey
        }
        if let envKey = environmentAPIKey {
            return envKey
        }
        return KeychainManager.shared.apiKey ?? ""
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("API Configuration") {
                    // Show status if environment key is detected
                    if environmentAPIKey != nil && anthropicAPIKey.isEmpty && !usingOverride {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Using API key from environment variable")
                                    .font(.caption)
                            }
                            
                            Button("Override with custom key") {
                                usingOverride = true
                            }
                            .buttonStyle(.link)
                        }
                    }
                    
                    // Always show input field if no effective key exists
                    if effectiveAPIKey.isEmpty || (environmentAPIKey == nil || !anthropicAPIKey.isEmpty || usingOverride) {
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
                        }
                        .help("Your Anthropic API key. Get one at https://console.anthropic.com/")
                        
                        if !anthropicAPIKey.isEmpty && environmentAPIKey != nil {
                            Button("Clear override (use environment variable)") {
                                anthropicAPIKey = ""
                                usingOverride = false
                                KeychainManager.shared.apiKey = nil
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        
                        if let error = saveError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    
                    if effectiveAPIKey.isEmpty {
                        Label("API key required for KeyPath to work", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                Section("Generation") {
                    Toggle("Stream Responses", isOn: $useStreaming)
                    VStack(alignment: .leading) {
                        Text("Temperature: \(temperature, specifier: "%.2f")")
                        Slider(value: $temperature, in: 0.0...2.0, step: 0.1)
                    }
                    .padding(.vertical, 4)
                    Picker("Model Provider", selection: $chatProvider) {
                        ForEach(ChatProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("System Instructions") {
                    TextEditor(text: $systemInstructions)
                        .frame(minHeight: 100)
                        .font(.body)
                }
            }
            .navigationTitle("Settings")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            // Load API key from Keychain if available
            if let keychainKey = KeychainManager.shared.apiKey, !keychainKey.isEmpty {
                anthropicAPIKey = keychainKey
            }
        }
        .onChange(of: anthropicAPIKey) { oldValue, newValue in
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
        .onDisappear { onDismiss?() }
    }
}
