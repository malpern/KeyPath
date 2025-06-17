import SwiftUI
import Foundation

struct KeyPathContentView: View {
    // MARK: - State Properties
    
    // UI State
    @State private var messages: [KeyPathMessage] = []
    @State private var inputText: String = ""
    @State private var isResponding = false
    @State private var showSettings = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    // KeyPath specific state
    @State private var pendingRemappingDescription: String?
    @State private var showRulePreview = false
    @State private var generatedRule: KanataRule?
    @State private var showOnboarding = false
    @StateObject private var securityManager = SecurityManager()
    @StateObject private var ruleHistory = RuleHistory()
    
    // Settings
    @AppStorage("useStreaming") private var useStreaming = AppSettings.useStreaming
    @AppStorage("temperature") private var temperature = AppSettings.temperature
    @AppStorage("systemInstructions") private var systemInstructions = ClaudePromptTemplates.systemInstructions
    @AppStorage("chatProvider") private var chatProvider = AppSettings.chatProvider
    
    @State private var provider: ChatModelProvider?
    @State private var streamingTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    // System Status (only show if there are issues)
                    if !securityManager.canInstallRules() {
                        SystemStatusView(securityManager: securityManager)
                            .padding()
                    }
                    
                    KeyPathChatMessagesView(
                        messages: messages,
                        isResponding: isResponding,
                        onInstallRule: handleInstallRule
                    )
                }
                
                // Floating Input Field
                VStack {
                    Spacer()
                    inputField
                        .padding(20)
                }
            }
            .navigationTitle("KeyPath")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .sheet(isPresented: $showSettings) {
                SettingsView {
                    provider = makeProvider()
                }
            }
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
        }
        .onAppear {
            provider = makeProvider()
            
            // Show welcome message if this is first launch
            if messages.isEmpty {
                showWelcomeMessage()
            }
            
            // Check if we should show onboarding
            if !securityManager.canInstallRules() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showOnboarding = true
                }
            }
        }
        .onChange(of: chatProvider) {
            provider = makeProvider()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            resetConversation()
        }
    }
    
    // MARK: - Subviews
    
    private var inputField: some View {
        ZStack {
            TextField("Describe your keyboard remapping...", text: $inputText, axis: .vertical)
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
                                .padding(.trailing, 8)
            }
        }
            }
    
    private var isSendButtonDisabled: Bool {
        return inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }
    
    // MARK: - KeyPath Specific Methods
    
    private func handleInstallRule(_ rule: KanataRule) {
        // Directly install the rule since we already have it
        installRule(rule)
    }
    
    private func installRule(_ rule: KanataRule) {
        let installer = KanataInstaller()
        let security = SecurityManager()
        
        // First check if Kanata is set up
        if !security.canInstallRules() {
            messages.append(KeyPathMessage(role: .assistant, text: "⚠️ Kanata setup required. Please check Settings for instructions."))
            return
        }
        
        messages.append(KeyPathMessage(role: .assistant, text: "Validating rule..."))
        
        // Validate the rule first
        installer.validateRule(rule.kanataRule) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.updateLastMessage(with: "✓ Rule validated successfully. Installing...")
                    
                    // Now install the rule
                    installer.installRule(rule) { installResult in
                        DispatchQueue.main.async {
                            switch installResult {
                            case .success(let backupPath):
                                self.ruleHistory.addRule(rule, backupPath: backupPath)
                                self.updateLastMessage(with: "✅ Rule installed successfully! \(rule.visualization.description)")
                            case .failure(let error):
                                self.updateLastMessage(with: "❌ Installation failed: \(error.localizedDescription)")
                            }
                        }
                    }
                    
                case .failure(let error):
                    self.updateLastMessage(with: "❌ Validation failed: \(error.localizedDescription)")
                }
            }
        }
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
                await MainActor.run {
                    self.showError(message: "An error occurred: \(error.localizedDescription)")
                    self.isResponding = false
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
    
    // MARK: - Session & Helpers
    
    private func makeProvider() -> ChatModelProvider {
        // Always use Anthropic for KeyPath
        return AnthropicModelProvider(systemInstructions: ClaudePromptTemplates.systemInstructions, temperature: temperature)
    }
    
    private func resetConversation() {
        stopStreaming()
        messages.removeAll()
        pendingRemappingDescription = nil
        generatedRule = nil
    }
    
    private func undoLastRule() {
        guard let lastRule = ruleHistory.getLastRule() else { return }
        
        let installer = KanataInstaller()
        messages.append(KeyPathMessage(role: .assistant, text: "Undoing last rule: \(lastRule.rule.visualization.description)..."))
        
        installer.undoLastRule(backupPath: lastRule.backupPath) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.ruleHistory.removeLastRule()
                    self.updateLastMessage(with: "✅ Successfully undid the last rule. Your keyboard has been restored.")
                case .failure(let error):
                    self.updateLastMessage(with: "❌ Failed to undo: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showWelcomeMessage() {
        // Show animated logo first
        let logoMessage = KeyPathMessage(role: .assistant, text: "LOGO_VIEW")
        messages.append(logoMessage)
        
        // Then show welcome text after a brief delay to let logo animate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let welcomeText = """
            Welcome to KeyPath! I can help you create custom keyboard remapping rules. Here's what I can do:

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

struct KeyPathChatMessagesView: View {
    let messages: [KeyPathMessage]
    let isResponding: Bool
    let onInstallRule: (KanataRule) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack {
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
                .padding(.bottom, 90) // Space for floating input field
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
