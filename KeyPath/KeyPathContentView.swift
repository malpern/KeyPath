import SwiftUI
import Foundation

struct KeyPathContentView: View {
    // MARK: - State Properties

    // UI State
    @State private var messages: [KeyPathMessage] = []
    @State private var inputText: String = ""
    @State private var isResponding = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // System Status (only show if there are issues)
                if !securityManager.canInstallRules() {
                    SystemStatusView(securityManager: securityManager)
                        .padding()
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
        }
        .onAppear {
            provider = makeProvider()

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
                .onSubmit {
                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        handleSendOrStop()
                    }
                }

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

        print("🔧 DEBUG: installRule called with rule: \(rule.explanation)")
        print("🔧 DEBUG: canInstallRules = \(security.canInstallRules())")
        print("🔧 DEBUG: isKanataInstalled = \(security.isKanataInstalled)")
        print("🔧 DEBUG: hasConfigAccess = \(security.hasConfigAccess)")

        // First check if Kanata is set up
        if !security.canInstallRules() {
            messages.append(KeyPathMessage(role: .assistant, text: "⚠️ Kanata setup required. Please check Settings for instructions."))
            return
        }

        messages.append(KeyPathMessage(role: .assistant, text: "Validating rule..."))

        // Validate the rule first
        installer.validateRule(rule.completeKanataConfig) { result in
            print("🔧 DEBUG: Validation result: \(result)")
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("🔧 DEBUG: Validation successful, now installing...")
                    self.updateLastMessage(with: "✓ Rule validated successfully. Installing...")

                    // Now install the rule
                    installer.installRule(rule) { installResult in
                        print("🔧 DEBUG: Installation result: \(installResult)")
                        DispatchQueue.main.async {
                            switch installResult {
                            case .success(let backupPath):
                                print("🔧 DEBUG: Installation successful, backup at: \(backupPath)")
                                self.ruleHistory.addRule(rule, backupPath: backupPath)
                                self.updateLastMessage(with: "✅ Rule installed successfully! \(rule.visualization.description)\n\n💡 To apply the changes, restart Kanata or run: `sudo kanata --cfg ~/.config/kanata/kanata.kbd`")
                                SoundManager.shared.playSound(.success)
                            case .failure(let error):
                                print("🔧 DEBUG: Installation failed: \(error)")
                                self.updateLastMessage(with: error.userFriendlyMessage)
                            }
                        }
                    }

                case .failure(let error):
                    print("🔧 DEBUG: Validation failed: \(error)")
                    self.handleValidationError(error)
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
                await MainActor.run {
                    let userFriendlyMessage = self.getUserFriendlyErrorMessage(from: error)
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
        let userMessage = error.userFriendlyMessage

        if error.isRecoverable {
            // For recoverable errors, provide helpful suggestions and try to auto-recover
            self.updateLastMessage(with: userMessage + "\n\n🔄 KeyPath can try to fix this automatically. Would you like to:")

            // Add recovery options based on error type
            switch error {
            case .recoverableValidationError(let errorMsg, let suggestedFix):
                if errorMsg.contains("Invalid source key") || errorMsg.contains("Invalid target key") {
                    self.suggestKeyCorrection(suggestedFix)
                } else if errorMsg.contains("format") {
                    self.suggestFormatCorrection(suggestedFix)
                } else {
                    self.updateLastMessage(with: userMessage)
                }
            default:
                self.updateLastMessage(with: userMessage)
            }
        } else {
            // For non-recoverable errors, provide clear guidance
            self.updateLastMessage(with: userMessage)

            // Auto-fix some common issues
            switch error {
            case .configDirectoryNotFound, .configFileNotFound:
                self.autoFixKanataSetup()
            default:
                break
            }
        }
    }

    private func suggestKeyCorrection(_ suggestion: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.messages.append(KeyPathMessage(
                role: .assistant,
                text: "💡 \(suggestion)\n\nTry describing your mapping again, or ask me something like:\n• \"Map caps lock to escape\"\n• \"Make space key act as shift\"\n• \"Change a to b\""
            ))
        }
    }

    private func suggestFormatCorrection(_ suggestion: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.messages.append(KeyPathMessage(
                role: .assistant,
                text: "💡 \(suggestion)\n\nI understand natural language! You can say:\n• \"caps lock to escape\"\n• \"map a to b\"\n• \"space bar as shift key\""
            ))
        }
    }

    private func autoFixKanataSetup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateLastMessage(with: "🔄 Setting up Kanata configuration automatically...")

            let installer = KanataInstaller()
            let setupResult = installer.checkKanataSetup()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                switch setupResult {
                case .success:
                    self.updateLastMessage(with: "✅ Kanata setup complete! You can now create keyboard rules.")
                case .failure(let setupError):
                    self.updateLastMessage(with: "❌ Auto-setup failed: \(setupError.localizedDescription)")
                }
            }
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
                    self.updateLastMessage(with: "✅ Successfully undid the last rule. Your keyboard has been restored.\n\n💡 To apply the changes, restart Kanata or run: `sudo kanata --cfg ~/.config/kanata/kanata.kbd`")
                    SoundManager.shared.playSound(.deactivation)
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

    private func getUserFriendlyErrorMessage(from error: Error) -> String {
        let errorString = error.localizedDescription.lowercased()

        // Check for specific error patterns and provide helpful messages
        if errorString.contains("x-api-key") || errorString.contains("authentication") {
            return """
            API Key Missing or Invalid

            To use KeyPath, you need to add your Anthropic API key:

            1. Open Settings (⌘,)
            2. Enter your Anthropic API key
            3. If you don't have one, get it at:
               https://console.anthropic.com/

            Your API key should start with 'sk-ant-api...'
            """
        } else if errorString.contains("network") || errorString.contains("connection") {
            return """
            Network Connection Error

            Please check your internet connection and try again.
            If the problem persists, the Anthropic API may be temporarily unavailable.
            """
        } else if errorString.contains("rate limit") {
            return """
            Rate Limit Exceeded

            You've made too many requests. Please wait a moment and try again.
            Consider upgrading your Anthropic plan for higher limits.
            """
        } else if errorString.contains("invalid request") || errorString.contains("bad request") {
            return """
            Invalid Request

            There was a problem with your request. Please try rephrasing your keyboard remapping description.
            """
        } else {
            // Generic error with the actual error for debugging
            return """
            An error occurred while processing your request.

            Error details: \(error.localizedDescription)

            If this continues, please check:
            - Your API key in Settings (⌘,)
            - Your internet connection
            - The Anthropic API status
            """
        }
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
