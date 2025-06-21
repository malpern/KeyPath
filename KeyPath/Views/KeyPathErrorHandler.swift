import Foundation
import SwiftUI

// MARK: - Error Handling Helper

struct KeyPathErrorHandler {
    static func handleValidationError(
        _ error: KanataValidationError,
        appendMessage: @escaping (KeyPathMessage) -> Void,
        updateLastMessage: @escaping (String) -> Void
    ) {
        let userMessage = error.userFriendlyMessage

        if error.isRecoverable {
            // For recoverable errors, provide helpful suggestions and try to auto-recover
            updateLastMessage(userMessage + "\n\n🔄 KeyPath can try to fix this automatically. Would you like to:")

            // Add recovery options based on error type
            switch error {
            case .recoverableValidationError(let errorMsg, let suggestedFix):
                if errorMsg.contains("Invalid source key") || errorMsg.contains("Invalid target key") {
                    KeyPathErrorHandler.suggestKeyCorrection(suggestedFix, appendMessage: appendMessage)
                } else if errorMsg.contains("format") {
                    KeyPathErrorHandler.suggestFormatCorrection(suggestedFix, appendMessage: appendMessage)
                } else {
                    updateLastMessage(userMessage)
                }
            default:
                updateLastMessage(userMessage)
            }
        } else {
            // For non-recoverable errors, provide clear guidance
            updateLastMessage(userMessage)

            // Auto-fix some common issues
            switch error {
            case .configDirectoryNotFound, .configFileNotFound:
                KeyPathErrorHandler.autoFixKanataSetup(updateLastMessage: updateLastMessage)
            default:
                break
            }
        }
    }

    private static func suggestKeyCorrection(_ suggestion: String, appendMessage: @escaping (KeyPathMessage) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            appendMessage(KeyPathMessage(
                role: .assistant,
                text: "💡 \(suggestion)\n\nTry describing your mapping again, or ask me something like:\n• \"Map caps lock to escape\"\n• \"Make space key act as shift\"\n• \"Change a to b\""
            ))
        }
    }

    private static func suggestFormatCorrection(_ suggestion: String, appendMessage: @escaping (KeyPathMessage) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            appendMessage(KeyPathMessage(
                role: .assistant,
                text: "💡 \(suggestion)\n\nI understand natural language! You can say:\n• \"caps lock to escape\"\n• \"map a to b\"\n• \"space bar as shift key\""
            ))
        }
    }

    private static func autoFixKanataSetup(updateLastMessage: @escaping (String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            updateLastMessage("🔄 Setting up Kanata configuration automatically...")

            let installer = KanataInstaller()
            let setupResult = installer.checkKanataSetup()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                switch setupResult {
                case .success:
                    updateLastMessage("✅ Kanata setup complete! You can now create keyboard rules.")
                case .failure(let setupError):
                    updateLastMessage("❌ Auto-setup failed: \(setupError.localizedDescription)")
                }
            }
        }
    }
}
