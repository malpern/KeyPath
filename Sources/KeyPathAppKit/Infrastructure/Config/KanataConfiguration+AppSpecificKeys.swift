import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import Network

extension KanataConfiguration {
    // MARK: - App-Specific Key Support

    /// Load the set of input keys that have app-specific overrides.
    /// These keys should use @kp-{key} aliases in the base layer to enable per-app behavior.
    static func loadAppSpecificKeys() -> Set<String> {
        let path = (WizardSystemPaths.userConfigDirectory as NSString)
            .appendingPathComponent("AppKeymaps.json")

        AppLogger.shared.log("🔍 [ConfigGen] loadAppSpecificKeys: checking path \(path)")

        guard FileManager.default.fileExists(atPath: path) else {
            AppLogger.shared.log("⚠️ [ConfigGen] loadAppSpecificKeys: file does not exist")
            return []
        }

        guard let data = FileManager.default.contents(atPath: path) else {
            AppLogger.shared.log("⚠️ [ConfigGen] loadAppSpecificKeys: could not read file contents")
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // Match AppKeymapStore's encoding

        guard let keymaps = try? decoder.decode([AppKeymap].self, from: data) else {
            AppLogger.shared.log("⚠️ [ConfigGen] loadAppSpecificKeys: JSON decode failed")
            return []
        }

        AppLogger.shared.log("🔍 [ConfigGen] loadAppSpecificKeys: found \(keymaps.count) keymaps")

        // Collect all input keys from enabled keymaps
        var keys = Set<String>()
        for keymap in keymaps where keymap.mapping.isEnabled {
            for override in keymap.overrides {
                keys.insert(override.inputKey.lowercased())
            }
        }

        AppLogger.shared.log("🔍 [ConfigGen] loadAppSpecificKeys: returning \(keys.count) keys: \(keys)")
        return keys
    }

    /// Convert a key name to its app-specific alias format (kp-{key}).
    /// Uses the same sanitization as AppConfigGenerator.
    static func appSpecificAliasName(for key: String) -> String {
        let sanitized = key.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        guard !sanitized.isEmpty else {
            let hash = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return "@kp-key-\(String(format: "%04x", hash % 65521))"
        }

        if let first = sanitized.first, !first.isLetter {
            return "@kp-key-\(sanitized)"
        }

        return "@kp-\(sanitized)"
    }
}
