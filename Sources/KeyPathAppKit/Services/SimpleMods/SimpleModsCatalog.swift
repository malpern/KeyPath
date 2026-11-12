import Foundation

/// Catalog of preset simple modifications
public final class SimpleModsCatalog: Sendable {
    public static let shared = SimpleModsCatalog()

    private init() {}

    /// Get all available presets
    public func getAllPresets() -> [SimpleModPreset] {
        [
            // Navigation & Modifiers
            SimpleModPreset(
                name: String(localized: "Caps Lock → Escape"),
                description: String(localized: "Maps Caps Lock to Escape key (useful for Vim users)"),
                category: String(localized: "Navigation"),
                fromKey: "caps",
                toKey: "esc"
            ),
            SimpleModPreset(
                name: String(localized: "Caps Lock → Control"),
                description: String(localized: "Maps Caps Lock to Control key"),
                category: String(localized: "Modifiers"),
                fromKey: "caps",
                toKey: "lctl"
            ),
            SimpleModPreset(
                name: String(localized: "Left Command → Right Command"),
                description: String(localized: "Swap left and right Command keys"),
                category: String(localized: "Modifiers"),
                fromKey: "lmet",
                toKey: "rmet"
            ),
            SimpleModPreset(
                name: String(localized: "Right Command → Left Command"),
                description: String(localized: "Swap right and left Command keys"),
                category: String(localized: "Modifiers"),
                fromKey: "rmet",
                toKey: "lmet"
            ),
            SimpleModPreset(
                name: String(localized: "Left Option → Right Option"),
                description: String(localized: "Swap left and right Option keys"),
                category: String(localized: "Modifiers"),
                fromKey: "lalt",
                toKey: "ralt"
            ),
            SimpleModPreset(
                name: String(localized: "Right Option → Left Option"),
                description: String(localized: "Swap right and left Option keys"),
                category: String(localized: "Modifiers"),
                fromKey: "ralt",
                toKey: "lalt"
            ),

            // Media & Function Keys
            SimpleModPreset(
                name: String(localized: "F13 → Play/Pause"),
                description: String(localized: "Maps F13 to media Play/Pause"),
                category: String(localized: "Media"),
                fromKey: "f13",
                toKey: "playpause"
            ),
            SimpleModPreset(
                name: String(localized: "F14 → Volume Down"),
                description: String(localized: "Maps F14 to Volume Down"),
                category: String(localized: "Media"),
                fromKey: "f14",
                toKey: "volup"
            ),
            SimpleModPreset(
                name: String(localized: "F15 → Volume Up"),
                description: String(localized: "Maps F15 to Volume Up"),
                category: String(localized: "Media"),
                fromKey: "f15",
                toKey: "voldown"
            ),

            // Common Swaps
            SimpleModPreset(
                name: String(localized: "Backspace → Delete"),
                description: String(localized: "Swap Backspace and Delete"),
                category: String(localized: "Common"),
                fromKey: "bspc",
                toKey: "del"
            ),
            SimpleModPreset(
                name: String(localized: "Delete → Backspace"),
                description: String(localized: "Swap Delete and Backspace"),
                category: String(localized: "Common"),
                fromKey: "del",
                toKey: "bspc"
            )
        ]
    }

    /// Get presets by category
    public func getPresetsByCategory() -> [String: [SimpleModPreset]] {
        var categorized: [String: [SimpleModPreset]] = [:]
        for preset in getAllPresets() {
            if categorized[preset.category] == nil {
                categorized[preset.category] = []
            }
            categorized[preset.category]?.append(preset)
        }
        return categorized
    }

    /// Find a preset by keys
    public func findPreset(fromKey: String, toKey: String) -> SimpleModPreset? {
        getAllPresets().first { $0.fromKey == fromKey && $0.toKey == toKey }
    }
}
