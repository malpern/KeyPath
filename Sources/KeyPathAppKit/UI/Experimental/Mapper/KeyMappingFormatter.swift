import Foundation
import KeyPathCore

/// Utility for converting key mappings to Kanata format.
///
/// Provides pure functions for:
/// - Converting KeySequence to Kanata format strings
/// - Converting layer names to RuleCollectionLayer
/// - Extracting domains from URLs
public enum KeyMappingFormatter {
    // MARK: - Key Sequence Formatting

    /// Map of key names to Kanata short forms
    private static let keyNameMap: [String: String] = [
        "space": "spc",
        "return": "ret",
        "enter": "ret",
        "escape": "esc",
        "backspace": "bspc",
        "delete": "del"
    ]

    /// Convert KeySequence to kanata format string
    ///
    /// - Parameter sequence: The key sequence to convert
    /// - Returns: Kanata-compatible string representation
    public static func toKanataFormat(_ sequence: KeySequence) -> String {
        let keyStrings = sequence.keys.map { keyPress -> String in
            var result = keyPress.baseKey.lowercased()

            // Handle special key names
            if let mapped = keyNameMap[result] {
                result = mapped
            }

            // Add modifiers (order: C-A-S-M- prefix)
            if keyPress.modifiers.contains(.control) { result = "C-" + result }
            if keyPress.modifiers.contains(.option) { result = "A-" + result }
            if keyPress.modifiers.contains(.shift) { result = "S-" + result }
            if keyPress.modifiers.contains(.command) { result = "M-" + result }

            return result
        }

        return keyStrings.joined(separator: " ")
    }

    // MARK: - Layer Conversion

    /// Convert layer name string to RuleCollectionLayer
    ///
    /// - Parameter name: The layer name (e.g., "base", "nav", "custom_layer")
    /// - Returns: The corresponding RuleCollectionLayer
    public static func layerFromString(_ name: String) -> RuleCollectionLayer {
        let lowercased = name.lowercased()
        switch lowercased {
        case "base":
            return .base
        case "nav", "navigation":
            return .navigation
        default:
            return .custom(name)
        }
    }

    // MARK: - URL Formatting

    /// Extract domain from URL for display purposes
    ///
    /// - Parameter url: The full URL string
    /// - Returns: Just the domain portion (e.g., "example.com" from "https://example.com/path")
    public static func extractDomain(from url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return cleaned.components(separatedBy: "/").first ?? url
    }
}
