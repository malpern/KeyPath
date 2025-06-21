import Foundation
import SwiftUI

// MARK: - Rule Installation Helper

struct RuleInstallationContext {
    let appendMessage: (KeyPathMessage) -> Void
    let ruleHistory: RuleHistory
    let updateLastMessage: (String) -> Void
    let onFocusInput: () -> Void
    let onValidationError: (KanataValidationError) -> Void
    let onKanataNotRunning: () -> Void
}

struct KeyPathRuleInstaller {
    static func installRule(_ rule: KanataRule, context: RuleInstallationContext) {
        let installer = KanataInstaller()
        let security = SecurityManager()

        DebugLogger.shared.log("🔧 DEBUG: installRule called with rule: \(rule.explanation)")
        DebugLogger.shared.log("🔧 DEBUG: rule.kanataRule: '\(rule.kanataRule)'")
        DebugLogger.shared.log("🔧 DEBUG: rule.completeKanataConfig:")
        DebugLogger.shared.log("🔧 DEBUG: \(rule.completeKanataConfig)")
        DebugLogger.shared.log("🔧 DEBUG: canInstallRules = \(security.canInstallRules())")
        DebugLogger.shared.log("🔧 DEBUG: isKanataInstalled = \(security.isKanataInstalled)")
        DebugLogger.shared.log("🔧 DEBUG: hasConfigAccess = \(security.hasConfigAccess)")

        // First check if Kanata is set up
        if !security.canInstallRules() {
            context.appendMessage(KeyPathMessage(role: .assistant, text: "⚠️ Kanata setup required. Please check Settings for instructions."))
            return
        }

        context.appendMessage(KeyPathMessage(role: .assistant, text: "Validating rule..."))

        // Validate the rule first
        installer.validateRule(rule.completeKanataConfig) { result in
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
                                
                                // Add to UserRuleManager for tracking in Settings
                                UserRuleManager.shared.addInstalledRule(rule, backupPath: backupPath)
                                
                                // Attempt auto-reload
                                let processManager = KanataProcessManager.shared
                                if processManager.isKanataRunning() {
                                    DebugLogger.shared.log("🔧 DEBUG: Kanata is running, attempting auto-reload...")
                                    let reloadSuccess = processManager.reloadKanata()
                                    
                                    if reloadSuccess {
                                        context.updateLastMessage("✅ Rule installed and activated! \(rule.visualization.description)\n\n🔄 Kanata configuration reloaded automatically. Your new rule is now active!")
                                    } else {
                                        context.updateLastMessage("✅ Rule installed successfully! \(rule.visualization.description)\n\n⚠️ Auto-reload failed. Please restart Kanata manually or run: `sudo pkill -SIGUSR1 kanata`")
                                    }
                                } else {
                                    context.updateLastMessage("✅ Rule installed successfully! \(rule.visualization.description)\n\n⚠️ Kanata is not running. Your rule has been saved but is not active yet.")
                                    // Trigger the alert dialog
                                    context.onKanataNotRunning()
                                }
                                
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
                    
                    // Attempt auto-reload after undo
                    let processManager = KanataProcessManager.shared
                    if processManager.isKanataRunning() {
                        let reloadSuccess = processManager.reloadKanata()
                        if reloadSuccess {
                            updateLastMessage("✅ Successfully undid the last rule and reloaded Kanata. Your keyboard has been restored.")
                        } else {
                            updateLastMessage("✅ Successfully undid the last rule.\n\n⚠️ Auto-reload failed. Please restart Kanata manually or run: `sudo pkill -SIGUSR1 kanata`")
                        }
                    } else {
                        updateLastMessage("✅ Successfully undid the last rule.\n\n⚠️ Kanata is not running. Start Kanata to see the changes: `sudo kanata --cfg ~/.config/kanata/kanata.kbd`")
                    }
                    
                    SoundManager.shared.playSound(.deactivation)
                case .failure(let error):
                    updateLastMessage("❌ Failed to undo: \(error.localizedDescription)")
                }
            }
        }
    }
}
