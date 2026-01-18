import Foundation

/// Utility for resolving layer information (icons, display names) from layer identifiers.
///
/// Provides a single source of truth for layer visual representation across the app.
/// Used by:
/// - Layer status indicators
/// - Rules display (Settings and Drawer)
/// - Layer picker UI
enum LayerInfo {
    /// Get the SF Symbol icon name for a layer
    /// - Parameter layerName: The layer identifier (e.g., "nav", "numpad", "vim")
    /// - Returns: SF Symbol name for the layer icon
    static func iconName(for layerName: String) -> String {
        let lower = layerName.lowercased()

        switch lower {
        case "base":
            return "keyboard"
        case "nav", "navigation", "vim":
            return "arrow.up.and.down.and.arrow.left.and.right"
        case "window", "window-mgmt":
            return "macwindow"
        case "numpad", "num":
            return "number"
        case "sym", "symbol", "sys1", "sys2":
            return "character"
        case "launcher", "quick launcher":
            return "app.badge"
        case "fn", "function":
            return "f.cursive"
        case "media":
            return "play.circle"
        default:
            return "square.3.layers.3d"
        }
    }

    /// Get a human-readable display name for a layer
    /// - Parameter layerName: The layer identifier (e.g., "nav", "numpad")
    /// - Returns: Formatted display name (e.g., "Navigation", "Numpad")
    static func displayName(for layerName: String) -> String {
        let lower = layerName.lowercased()

        switch lower {
        case "base":
            return "Base"
        case "nav":
            return "Nav"
        case "navigation":
            return "Navigation"
        case "vim":
            return "Vim"
        case "window", "window-mgmt":
            return "Window"
        case "numpad":
            return "Numpad"
        case "num":
            return "Num"
        case "sym", "symbol":
            return "Symbol"
        case "sys1":
            return "System 1"
        case "sys2":
            return "System 2"
        case "launcher":
            return "Launcher"
        case "quick launcher":
            return "Quick Launcher"
        case "fn", "function":
            return "Function"
        case "media":
            return "Media"
        default:
            // Capitalize first letter for unknown layers
            return layerName.prefix(1).uppercased() + layerName.dropFirst()
        }
    }

    /// Extract layer name from a layer-switch output string
    /// - Parameter output: The raw output string (e.g., "(layer-switch nav)" or "(Layer-Switch Nav)")
    /// - Returns: The layer name if found, nil otherwise
    static func extractLayerName(from output: String) -> String? {
        // Match patterns like:
        // (layer-switch nav)
        // (Layer-Switch Nav)
        // (layer-switch some-layer-name)
        let pattern = #"\(layer-switch\s+([^\)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let layerRange = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return String(output[layerRange]).trimmingCharacters(in: .whitespaces)
    }

    /// Check if an output string is a layer-switch action
    /// - Parameter output: The raw output string
    /// - Returns: true if this is a layer-switch action
    static func isLayerSwitch(_ output: String) -> Bool {
        output.lowercased().contains("layer-switch")
    }
}
