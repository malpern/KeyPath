import Foundation

/// Catalog of preset simple modifications
@MainActor
public final class SimpleModsCatalog {
    public static let shared = SimpleModsCatalog()
    
    private init() {}
    
    /// Get all available presets
    public func getAllPresets() -> [SimpleModPreset] {
        return [
            // Navigation & Modifiers
            SimpleModPreset(
                name: "Caps Lock → Escape",
                description: "Maps Caps Lock to Escape key (useful for Vim users)",
                category: "Navigation",
                fromKey: "caps",
                toKey: "esc"
            ),
            SimpleModPreset(
                name: "Caps Lock → Control",
                description: "Maps Caps Lock to Control key",
                category: "Modifiers",
                fromKey: "caps",
                toKey: "lctl"
            ),
            SimpleModPreset(
                name: "Left Command → Right Command",
                description: "Swap left and right Command keys",
                category: "Modifiers",
                fromKey: "lmet",
                toKey: "rmet"
            ),
            SimpleModPreset(
                name: "Right Command → Left Command",
                description: "Swap right and left Command keys",
                category: "Modifiers",
                fromKey: "rmet",
                toKey: "lmet"
            ),
            SimpleModPreset(
                name: "Left Option → Right Option",
                description: "Swap left and right Option keys",
                category: "Modifiers",
                fromKey: "lalt",
                toKey: "ralt"
            ),
            SimpleModPreset(
                name: "Right Option → Left Option",
                description: "Swap right and left Option keys",
                category: "Modifiers",
                fromKey: "ralt",
                toKey: "lalt"
            ),
            
            // Media & Function Keys
            SimpleModPreset(
                name: "F13 → Play/Pause",
                description: "Maps F13 to media Play/Pause",
                category: "Media",
                fromKey: "f13",
                toKey: "playpause"
            ),
            SimpleModPreset(
                name: "F14 → Volume Down",
                description: "Maps F14 to Volume Down",
                category: "Media",
                fromKey: "f14",
                toKey: "volup"
            ),
            SimpleModPreset(
                name: "F15 → Volume Up",
                description: "Maps F15 to Volume Up",
                category: "Media",
                fromKey: "f15",
                toKey: "voldown"
            ),
            
            // Common Swaps
            SimpleModPreset(
                name: "Backspace → Delete",
                description: "Swap Backspace and Delete",
                category: "Common",
                fromKey: "bspc",
                toKey: "del"
            ),
            SimpleModPreset(
                name: "Delete → Backspace",
                description: "Swap Delete and Backspace",
                category: "Common",
                fromKey: "del",
                toKey: "bspc"
            ),
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
        return getAllPresets().first { $0.fromKey == fromKey && $0.toKey == toKey }
    }
}

