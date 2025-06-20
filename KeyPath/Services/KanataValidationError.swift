import Foundation

enum KanataValidationError: Error, LocalizedError {
    case configDirectoryNotFound
    case configFileNotFound
    case kanataNotFound
    case kanataInstallationFailed(String)
    case karabinerConflict
    case validationFailed(String)
    case writeFailed(String)
    case reloadFailed(String)
    case recoverableValidationError(String, suggestedFix: String)

    var errorDescription: String? {
        switch self {
        case .configDirectoryNotFound:
            return "Kanata configuration directory not found at ~/.config/kanata/"
        case .configFileNotFound:
            return "Kanata configuration file not found at ~/.config/kanata/kanata.kbd"
        case .kanataNotFound:
            return "Kanata executable not found. Please install Kanata using 'brew install kanata' or download from GitHub."
        case .kanataInstallationFailed(let message):
            return "Failed to install Kanata: \(message)"
        case .karabinerConflict:
            return "Karabiner-Elements is running and conflicts with Kanata. Please quit Karabiner-Elements before using KeyPath."
        case .validationFailed(let message):
            return "Rule validation failed: \(message)"
        case .writeFailed(let message):
            return "Failed to write configuration: \(message)"
        case .reloadFailed(let message):
            return "Failed to reload Kanata: \(message)"
        case .recoverableValidationError(let error, let suggestedFix):
            return "⚠️ \(error)\n\n💡 Suggested fix: \(suggestedFix)"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .recoverableValidationError:
            return true
        default:
            return false
        }
    }

    var userFriendlyMessage: String {
        switch self {
        case .configDirectoryNotFound, .configFileNotFound:
            return "📁 Kanata setup incomplete. KeyPath will create the necessary files automatically."
        case .kanataNotFound:
            return "⚙️ Kanata not installed. Please install it with: brew install kanata"
        case .karabinerConflict:
            return "⚠️ Karabiner-Elements conflicts with Kanata. Please quit Karabiner-Elements first."
        case .validationFailed(let message):
            return createUserFriendlyValidationMessage(message)
        case .recoverableValidationError(let error, let fix):
            return "⚠️ \(error)\n\n💡 Try: \(fix)"
        case .kanataInstallationFailed, .writeFailed, .reloadFailed:
            return "❌ Installation failed. Please check your Kanata setup and try again."
        }
    }

    private func createUserFriendlyValidationMessage(_ message: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("invalid key") {
            return "🔤 Invalid key name. Please use standard key names like 'a', 'caps', 'esc', etc."
        } else if lowercased.contains("empty") {
            return "📝 Empty rule detected. Please specify which keys to remap."
        } else if lowercased.contains("format") {
            return "📋 Invalid format. Try using 'caps lock to escape' or 'a to b' format."
        } else if lowercased.contains("parentheses") {
            return "🔧 Syntax error detected. KeyPath will try to fix this automatically."
        } else if lowercased.contains("undefined alias") {
            return "🔗 Configuration error detected. KeyPath will rebuild the config."
        } else {
            return "⚠️ Rule validation failed. KeyPath will try to create a corrected version."
        }
    }
}
