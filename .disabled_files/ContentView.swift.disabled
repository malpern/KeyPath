//
//  ContentView.swift
//  KeyPath
//
//  Created by Pallav Agarwal on 6/9/25.
//

import SwiftUI
import Foundation

/// Main chat interface view
struct ContentView: View {
    // MARK: - State Properties
    
    // UI State
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isResponding = false
    @State private var showSettings = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    // Settings
    @AppStorage("useStreaming") private var useStreaming = AppSettings.useStreaming
    @AppStorage("temperature") private var temperature = AppSettings.temperature
    @AppStorage("systemInstructions") private var systemInstructions = AppSettings.systemInstructions
    @AppStorage("chatProvider") private var chatProvider = AppSettings.chatProvider
    
    // Haptics
#if os(iOS)
    private let hapticStreamGenerator = UISelectionFeedbackGenerator()
#endif
    
    @State private var provider: ChatModelProvider?
    @State private var streamingTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            ZStack {
                ChatMessagesView(messages: messages, isResponding: isResponding)
                // Floating Input Field
                VStack {
                    Spacer()
                    inputField
                        .padding(20)
                }
            }
            .navigationTitle(chatProvider.displayName)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSettings) {
                SettingsView {
                    provider = makeProvider() // Reset provider on settings change
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            provider = makeProvider()
        }
        .onChange(of: chatProvider) {
            provider = makeProvider()
        }
        .onChange(of: temperature) {
            provider = makeProvider()
        }
        .onChange(of: systemInstructions) {
            provider = makeProvider()
        }
    }
    
    // MARK: - Subviews
    
    /// Floating input field with send/stop button
    private var inputField: some View {
        ZStack {
            TextField("Ask anything", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .frame(minHeight: 22)
                .disabled(isResponding)
                .onSubmit {
                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        handleSendOrStop()
                    }
                }
                .padding(16)
            
            HStack {
                Spacer()
                Button(action: handleSendOrStop) {
                    Image(systemName: isResponding ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(isSendButtonDisabled ? Color.gray.opacity(0.6) : .primary)
                }
                .disabled(isSendButtonDisabled)
                .animation(.easeInOut(duration: 0.2), value: isResponding)
                .animation(.easeInOut(duration: 0.2), value: isSendButtonDisabled)
                                .padding(.trailing, 8)
            }
        }
            }
    
    private var isSendButtonDisabled: Bool {
        return inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
#if os(iOS)
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: resetConversation) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gearshape")
            }
        }
#else
        ToolbarItem {
            Button(action: resetConversation) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
        }
        ToolbarItem {
            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gearshape")
            }
        }
#endif
    }
    
    // MARK: - Model Interaction
    
    private func handleSendOrStop() {
        if isResponding {
            stopStreaming()
        } else {
            sendMessage()
        }
    }
    
    private func sendMessage() {
        isResponding = true
        let userMessage = ChatMessage(role: .user, text: inputText)
        messages.append(userMessage)
        let prompt = inputText
        inputText = ""
        messages.append(ChatMessage(role: .assistant, text: ""))
        guard let provider = provider else {
            showError(message: "No provider available.")
            isResponding = false
            return
        }

        if false { // Temporarily disable streaming to debug
            streamingTask = Task {
                do {
                    try await provider.streamMessage(prompt) { partial in
                        Task { @MainActor in
                            updateLastMessage(with: partial)
                        }
                    }
                } catch {
                    await MainActor.run {
                        showError(message: "An error occurred: \(error.localizedDescription)")
                    }
                }
                await MainActor.run {
                    isResponding = false
                    streamingTask = nil
                }
            }
        } else {
            Task {
                do {
                    let response = try await provider.sendMessage(prompt)
                    await MainActor.run {
                        updateLastMessage(with: response)
                        isResponding = false
                    }
                } catch {
                    await MainActor.run {
                        showError(message: "An error occurred: \(error.localizedDescription)")
                        isResponding = false
                    }
                }
            }
        }
    }
    
    private func stopStreaming() {
        streamingTask?.cancel()
    }
    
    @MainActor
    private func updateLastMessage(with text: String) {
        messages[messages.count - 1].text = text
    }
    
    // MARK: - Session & Helpers
    
    private func makeProvider() -> ChatModelProvider {
        print("Making provider: \(chatProvider.rawValue)")
        switch chatProvider {
        case .apple:
            // AppleModelProvider not available in this environment
            return AnthropicModelProvider(systemInstructions: systemInstructions, temperature: temperature)
        case .anthropic:
            return AnthropicModelProvider(systemInstructions: systemInstructions, temperature: temperature)
        }
    }
    
    private func resetConversation() {
        stopStreaming()
        messages.removeAll()
    }
    
    @MainActor
    private func showError(message: String) {
        self.errorMessage = message
        self.showErrorAlert = true
        self.isResponding = false
    }
}

struct ChatMessagesView: View {
    let messages: [ChatMessage]
    let isResponding: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack {
                    ForEach(messages) { message in
                        MessageView(message: message, isResponding: isResponding)
                            .id(message.id)
                    }
                }
                .padding()
                .padding(.bottom, 90) // Space for floating input field
            }
            .onChange(of: messages.last?.text) {
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
