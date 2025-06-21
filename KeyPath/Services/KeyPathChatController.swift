import Foundation
import SwiftUI

// Protocol for testing purposes - allows mock providers to implement DirectResponse methods
protocol KeyPathTestableProvider: ChatModelProvider {
    func sendDirectMessageWithHistory(_ messages: [KeyPathMessage]) async throws -> DirectResponse
}

@Observable
class KeyPathChatController {
    // MARK: - Published Properties

    var messages: [KeyPathMessage] = []
    var isResponding = false
    var errorMessage = ""
    var showErrorAlert = false

    // Rule-related state
    var pendingRemappingDescription: String?
    var generatedRule: KanataRule?
    var showRulePreview = false

    // Dependencies
    private let securityManager: SecurityManager
    private let ruleHistory: RuleHistory
    private let modelProvider: ChatModelProvider
    private let kanataInstaller: KanataInstaller
    private let userRuleManager: UserRuleManager
    private let errorMessageGenerator: LLMErrorMessageGenerator

    // MARK: - Initialization

    init(
        securityManager: SecurityManager = SecurityManager(),
        ruleHistory: RuleHistory = RuleHistory(),
        modelProvider: ChatModelProvider,
        kanataInstaller: KanataInstaller? = nil,
        userRuleManager: UserRuleManager = UserRuleManager(),
        errorMessageGenerator: LLMErrorMessageGenerator? = nil
    ) {
        self.securityManager = securityManager
        self.ruleHistory = ruleHistory
        self.modelProvider = modelProvider
        
        // Pass LLM provider to kanataInstaller if it's an AnthropicModelProvider
        let anthropicProvider = modelProvider as? AnthropicModelProvider
        self.kanataInstaller = kanataInstaller ?? KanataInstaller(llmProvider: anthropicProvider)
        
        self.userRuleManager = userRuleManager
        self.errorMessageGenerator = errorMessageGenerator ?? LLMErrorMessageGenerator(llmProvider: anthropicProvider)
    }

    // MARK: - Public Methods

    func sendMessage(_ userInput: String) async {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        await prepareForMessage(userInput)
        await processMessage()
    }

    func installRule(_ rule: KanataRule) {
        // First check if Kanata is set up
        if !securityManager.canInstallRules() {
            messages.append(KeyPathMessage(role: .assistant, text: "⚠️ Kanata setup required. Please check Settings for instructions."))
            return
        }

        messages.append(KeyPathMessage(role: .assistant, text: "Validating rule..."))

        // Validate the rule first
        kanataInstaller.validateRule(rule.kanataRule) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.updateLastMessage(with: "✓ Rule validated successfully. Installing...")

                    // Use the UserRuleManager to add the rule
                    self.userRuleManager.addRule(rule) { addResult in
                        DispatchQueue.main.async {
                            switch addResult {
                            case .success(let userRule):
                                // Also add to legacy rule history for undo functionality
                                if let backupPath = userRule.backupPath {
                                    self.ruleHistory.addRule(rule, backupPath: backupPath)
                                }
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

    func undoLastRule() {
        guard let lastRule = ruleHistory.getLastRule() else { return }

        messages.append(KeyPathMessage(role: .assistant, text: "Undoing last rule: \(lastRule.rule.visualization.description)..."))

        kanataInstaller.undoLastRule(backupPath: lastRule.backupPath) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
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

    func resetConversation() {
        messages.removeAll()
        pendingRemappingDescription = nil
        generatedRule = nil
        isResponding = false
    }

    func showWelcomeMessage() {
        // Show animated logo first
        let logoMessage = KeyPathMessage(role: .assistant, text: "LOGO_VIEW")
        messages.append(logoMessage)

        // Then show welcome text after a brief delay to let logo animate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
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
            self?.messages.append(welcomeMessage)
        }
    }

    // MARK: - Private Methods

    private func handleResponse(_ response: DirectResponse) {
        switch response {
        case .rule(let rule):
            // Replace the last empty message with a rule message
            messages[messages.count - 1] = KeyPathMessage(role: .assistant, rule: rule)
        case .clarification(let text):
            // Replace the last empty message with a text message
            messages[messages.count - 1] = KeyPathMessage(role: .assistant, text: text)
        }
        isResponding = false
    }

    private func updateLastMessage(with text: String) {
        if !messages.isEmpty {
            messages[messages.count - 1] = KeyPathMessage(role: .assistant, text: text)
        }
    }

    private func showError(message: String) {
        errorMessage = message
        showErrorAlert = true
        isResponding = false
    }

    // MARK: - Message Processing Helpers

    private func prepareForMessage(_ userInput: String) async {
        await MainActor.run {
            isResponding = true
            let userMessage = KeyPathMessage(role: .user, text: userInput)
            messages.append(userMessage)
            messages.append(KeyPathMessage(role: .assistant, text: ""))
        }
    }

    private func processMessage() async {
        if let anthropicProvider = modelProvider as? AnthropicModelProvider {
            await handleAnthropicProvider(anthropicProvider)
        } else if let mockProvider = modelProvider as? KeyPathTestableProvider {
            await handleMockProvider(mockProvider)
        } else {
            await MainActor.run {
                showError(message: "KeyPath requires Anthropic Claude")
            }
        }
    }

    private func handleAnthropicProvider(_ provider: AnthropicModelProvider) async {
        do {
            let response = try await provider.sendDirectMessageWithHistory(messages)
            await MainActor.run {
                handleResponse(response)
            }
        } catch {
            await handleProviderError(error, providerName: "Anthropic Claude")
        }
    }

    private func handleMockProvider(_ provider: KeyPathTestableProvider) async {
        do {
            let response = try await provider.sendDirectMessageWithHistory(messages)
            await MainActor.run {
                handleResponse(response)
            }
        } catch {
            await handleProviderError(error, providerName: "Mock/Test Provider")
        }
    }

    private func handleProviderError(_ error: Error, providerName: String) async {
        let context = ErrorContext(
            operation: "Sending message to \(providerName)",
            userInput: messages.dropLast().last?.displayText,
            additionalInfo: ["provider": providerName]
        )
        let userFriendlyMessage = await errorMessageGenerator.generateUserFriendlyErrorMessage(from: error, context: context)
        
        await MainActor.run {
            showError(message: userFriendlyMessage)
            // Remove the empty message we added
            if messages.last?.displayText.isEmpty == true {
                messages.removeLast()
            }
        }
    }

}
