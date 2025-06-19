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
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""
    @State private var showAPIKey = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("API Configuration") {
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
                    
                    if anthropicAPIKey.isEmpty {
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
        .onDisappear { onDismiss?() }
    }
}
