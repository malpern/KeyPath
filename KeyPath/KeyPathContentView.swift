import Foundation
import SwiftUI

struct KeyPathContentView: View {
    // MARK: - State Properties

    // UI State
    @State private var messages: [KeyPathMessage] = []
    @State private var inputText: String = ""
    @State private var isResponding = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showKanataNotRunningAlert = false
    @FocusState private var isInputFocused: Bool

    // KeyPath specific state
    @State private var pendingRemappingDescription: String?
    @State private var showRulePreview = false
    @State private var generatedRule: KanataRule?
    @State private var showOnboarding = false
    @State private var securityManager = SecurityManager()
    @State private var ruleHistory = RuleHistory()
    @State private var showTitleInHeader = false

    // Settings
    @AppStorage("useStreaming") private var useStreaming = AppSettings.useStreaming
    @AppStorage("temperature") private var temperature = AppSettings.temperature
    @AppStorage("systemInstructions") private var systemInstructions = ClaudePromptTemplates.systemInstructions
    @AppStorage("chatProvider") private var chatProvider = AppSettings.chatProvider

    @State private var provider: ChatModelProvider?
    @State private var streamingTask: Task<Void, Never>?
    @State private var errorMessageGenerator: LLMErrorMessageGenerator?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // System Status (only show if there are issues)
                if !securityManager.canInstallRules() {
                    SystemStatusView(securityManager: securityManager)
                        .padding()
                } else {
                    // Show Kanata status
                    KanataStatusView()
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Messages area
                KeyPathChatMessagesView(
                    messages: messages,
                    isResponding: isResponding,
                    showTitleInHeader: $showTitleInHeader,
                    onInstallRule: handleInstallRule
                )

                // Input field at bottom
                inputField
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .navigationTitle(showTitleInHeader ? "KeyPath" : "")
            .toolbarTitleDisplayMode(.inline)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(
                    securityManager: securityManager,
                    showOnboarding: $showOnboarding
                )
            }
            .sheet(isPresented: $showRulePreview) {
                if let rule = generatedRule {
                    RulePreviewView(rule: rule) { confirmed in
                        if confirmed {
                            installRule(rule)
                        }
                        showRulePreview = false
                        generatedRule = nil
                    }
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .alert("Kanata Not Running", isPresented: $showKanataNotRunningAlert) {
                Button("OK") {}
                Button("How to Start Kanata") {
                    // Could open help documentation or show instructions
                }
            } message: {
                Text("Kanata is not currently running. Your rule has been saved but won't be active until you start Kanata.\n\nTo start Kanata, run:\nsudo kanata --cfg ~/.config/kanata/kanata.kbd")
            }
        }
        .onAppear {
            provider = makeProvider()
            errorMessageGenerator = LLMErrorMessageGenerator(llmProvider: provider as? AnthropicModelProvider)

            // Show welcome message if this is first launch
            if messages.isEmpty {
                showWelcomeMessage()
            }

            // Check if we should show onboarding
            if !securityManager.canInstallRules() || !KeychainManager.shared.hasAPIKey() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showOnboarding = true
                }
            }
        }
        .onChange(of: chatProvider) {
            provider = makeProvider()
            errorMessageGenerator = LLMErrorMessageGenerator(llmProvider: provider as? AnthropicModelProvider)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            resetConversation()
        }
    }

    // MARK: - Subviews

    private var inputField: some View {
        HStack(spacing: 12) {
            TextField("Describe your keyboard remapping...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...5)
                .frame(minHeight: 24)
                .disabled(isResponding)
                .focused($isInputFocused)
                .onSubmit {
                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        handleSendOrStop()
                    }
                }
                .accessibilityLabel("Keyboard remapping description")
                .accessibilityHint("Describe the keyboard mapping you want to create, like 'caps lock to escape'")

            Button(action: handleSendOrStop) {
                Image(systemName: isResponding ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(isSendButtonDisabled ? .secondary : .accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(isSendButtonDisabled)
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: isResponding)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .onTapGesture {
            // Make the entire input area tappable to focus the text field
            isInputFocused = true
        }
        .onAppear {
            // Auto-focus when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isInputFocused = true
            }
        }
    }

    private var isSendButtonDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    // MARK: - KeyPath Specific Methods

    private func handleInstallRule(_ rule: KanataRule) {
        DebugLogger.shared.log("🔧 DEBUG: handleInstallRule called with rule: \(rule.explanation)")
        DebugLogger.shared.log("🔧 DEBUG: rule.kanataRule = '\(rule.kanataRule)'")
        // Directly install the rule since we already have it
        installRule(rule)
    }

    private func installRule(_ rule: KanataRule) {
        let context = RuleInstallationContext(
            appendMessage: { message in self.messages.append(message) },
            ruleHistory: ruleHistory,
            updateLastMessage: { text in self.updateLastMessage(with: text) },
            onFocusInput: { self.isInputFocused = true },
            onValidationError: { error in self.handleValidationError(error) },
            onKanataNotRunning: { self.showKanataNotRunningAlert = true }
        )
        KeyPathRuleInstaller.installRule(rule, context: context)
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
        let userMessage = KeyPathMessage(role: .user, text: inputText)
        messages.append(userMessage)
        inputText = ""
        messages.append(KeyPathMessage(role: .assistant, text: ""))

        // Always create a fresh provider to ensure we have the latest API key
        provider = makeProvider()

        guard let anthropicProvider = provider as? AnthropicModelProvider else {
            showError(message: "KeyPath requires Anthropic Claude")
            isResponding = false
            return
        }

        // Use direct generation with full conversation history
        Task {
            do {
                let response = try await anthropicProvider.sendDirectMessageWithHistory(self.messages)
                await MainActor.run {
                    switch response {
                    case .rule(let rule):
                        // Replace the last empty message with a rule message
                        self.messages[self.messages.count - 1] = KeyPathMessage(role: .assistant, rule: rule)
                    case .clarification(let text):
                        // Replace the last empty message with a text message
                        self.messages[self.messages.count - 1] = KeyPathMessage(role: .assistant, text: text)
                    }
                    self.isResponding = false
                }
            } catch {
                let context = ErrorContext(
                    operation: "Sending message",
                    userInput: userMessage.displayText,
                    additionalInfo: ["provider": "Anthropic Claude"]
                )
                
                let userFriendlyMessage: String
                if let errorGen = self.errorMessageGenerator {
                    userFriendlyMessage = await errorGen.generateUserFriendlyErrorMessage(from: error, context: context)
                } else {
                    userFriendlyMessage = "Unable to process request: \(error.localizedDescription)"
                }
                
                await MainActor.run {
                    self.showError(message: userFriendlyMessage)
                    self.isResponding = false
                    // Remove the empty message we added
                    if self.messages.last?.displayText.isEmpty == true {
                        self.messages.removeLast()
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
        if !messages.isEmpty {
            messages[messages.count - 1] = KeyPathMessage(role: .assistant, text: text)
        }
    }

    // MARK: - Error Recovery

    private func handleValidationError(_ error: KanataValidationError) {
        KeyPathErrorHandler.handleValidationError(
            error,
            appendMessage: { message in self.messages.append(message) },
            updateLastMessage: { text in self.updateLastMessage(with: text) }
        )
    }

    // MARK: - Session & Helpers

    private func makeProvider() -> ChatModelProvider {
        // Always use Anthropic for KeyPath
        AnthropicModelProvider(systemInstructions: ClaudePromptTemplates.systemInstructions, temperature: temperature)
    }

    private func resetConversation() {
        stopStreaming()
        messages.removeAll()
        pendingRemappingDescription = nil
        generatedRule = nil
    }

    private func undoLastRule() {
        KeyPathRuleInstaller.undoLastRule(
            ruleHistory: ruleHistory,
            appendMessage: { message in self.messages.append(message) },
            updateLastMessage: { text in self.updateLastMessage(with: text) }
        )
    }

    private func showWelcomeMessage() {
        // Show animated logo first
        let logoMessage = KeyPathMessage(role: .assistant, text: "LOGO_VIEW")
        messages.append(logoMessage)

        // Then show welcome text after a brief delay to let logo animate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let welcomeText = """
            # Welcome to KeyPath!

            I can help you create custom keyboard remapping rules. Here's what I can do:

            - **Simple substitutions**: "Map Caps Lock to Escape" or "5 to 2"
            - **Tap-hold**: "Space bar taps space, but holding it acts as Shift"
            - **Multi-tap**: "F key: 1 tap = F, 2 taps = Ctrl+F, 3 taps = Cmd+F"
            - **Key sequences**: "Type 'email' to expand to your email address"
            - **Combos**: "A+S+D together outputs 'hello world'"
            - **Layers**: "Gaming mode that remaps WASD differently"

            Just describe what you want in plain English and I'll create the rule for you!
            """

            let welcomeMessage = KeyPathMessage(role: .assistant, text: welcomeText)
            self.messages.append(welcomeMessage)
        }
    }

    @MainActor
    private func showError(message: String) {
        self.errorMessage = message
        self.showErrorAlert = true
        self.isResponding = false
    }

}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct KeyPathChatMessagesView: View {
    let messages: [KeyPathMessage]
    let isResponding: Bool
    @Binding var showTitleInHeader: Bool
    let onInstallRule: (KanataRule) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack {
                    Text("KeyPath")
                        .font(.largeTitle.bold())
                        .padding(.top, 20)
                         .padding(.bottom, 10)
                        .opacity(showTitleInHeader ? 0 : 1)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scroll")).minY
                            )
                        })

                    ForEach(messages) { message in
                        KeyPathMessageView(
                            message: message,
                            isResponding: isResponding,
                            onInstallRule: onInstallRule
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Threshold can be adjusted.
                    // When the top of the title is scrolled above this point, show header title.
                    showTitleInHeader = value < 40
                }
            }
            .onChange(of: messages.last?.displayText) {
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
    KeyPathContentView()
}
