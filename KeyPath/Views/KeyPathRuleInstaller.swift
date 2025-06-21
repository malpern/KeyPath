import Foundation
import SwiftUI

// MARK: - Rule Installation Helper

struct RuleInstallationContext {
    let appendMessage: (KeyPathMessage) -> Void
    let ruleHistory: RuleHistory
    let updateLastMessage: (String) -> Void
    let onFocusInput: () -> Void
    let onValidationError: (KanataValidationError) -> Void
}

struct KeyPathRuleInstaller {
    static func installRule(_ rule: KanataRule, context: RuleInstallationContext) {
        let installer = KanataInstaller()
        let security = SecurityManager()

        print("🔧 DEBUG: installRule called with rule: \(rule.explanation)")
        print("🔧 DEBUG: canInstallRules = \(security.canInstallRules())")
        print("🔧 DEBUG: isKanataInstalled = \(security.isKanataInstalled)")
        print("🔧 DEBUG: hasConfigAccess = \(security.hasConfigAccess)")

        // First check if Kanata is set up
        if !security.canInstallRules() {
            context.appendMessage(KeyPathMessage(role: .assistant, text: "⚠️ Kanata setup required. Please check Settings for instructions."))
            return
        }

        context.appendMessage(KeyPathMessage(role: .assistant, text: "Validating rule..."))

        // Validate the rule first
        installer.validateRule(rule.kanataRule) { result in
            print("🔧 DEBUG: Validation result: \(result)")
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("🔧 DEBUG: Validation successful, now installing...")
                    context.updateLastMessage("✓ Rule validated successfully. Installing...")

                    // Now install the rule
                    installer.installRule(rule) { installResult in
                        print("🔧 DEBUG: Installation result: \(installResult)")
                        DispatchQueue.main.async {
                            switch installResult {
                            case .success(let backupPath):
                                print("🔧 DEBUG: Installation successful, backup at: \(backupPath)")
                                context.ruleHistory.addRule(rule, backupPath: backupPath)
                                context.updateLastMessage("✅ Rule installed successfully! \(rule.visualization.description)\n\n💡 To apply the changes, restart Kanata or run: `sudo kanata --cfg ~/.config/kanata/kanata.kbd`")
                                SoundManager.shared.playSound(.success)
                                
                                // Auto-focus input field for next rule
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    context.onFocusInput()
                                }
                            case .failure(let error):
                                print("🔧 DEBUG: Installation failed: \(error)")
                                context.updateLastMessage(error.userFriendlyMessage)
                            }
                        }
                    }

                case .failure(let error):
                    print("🔧 DEBUG: Validation failed: \(error)")
                    context.onValidationError(error)
                }
            }
        }
    }

    static func undoLastRule(
        ruleHistory: RuleHistory,
        appendMessage: @escaping (KeyPathMessage) -> Void,
        updateLastMessage: @escaping (String) -> Void
    ) {
        guard let lastRule = ruleHistory.getLastRule() else { return }

        let installer = KanataInstaller()
        appendMessage(KeyPathMessage(role: .assistant, text: "Undoing last rule: \(lastRule.rule.visualization.description)..."))

        installer.undoLastRule(backupPath: lastRule.backupPath) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    ruleHistory.removeLastRule()
                    updateLastMessage("✅ Successfully undid the last rule. Your keyboard has been restored.\n\n💡 To apply the changes, restart Kanata or run: `sudo kanata --cfg ~/.config/kanata/kanata.kbd`")
                    SoundManager.shared.playSound(.deactivation)
                case .failure(let error):
                    updateLastMessage("❌ Failed to undo: \(error.localizedDescription)")
                }
            }
        }
    }
}
