import Foundation

/// Generates Kanata key mappings to remap a QWERTY keyboard to an alternative layout.
///
/// This generator creates mappings that transform physical QWERTY key presses into
/// the corresponding characters of the target layout (Colemak, Dvorak, etc.).
///
/// ## Example
/// For Colemak, the physical 'E' key should output 'f':
/// - QWERTY position: E key (keyCode 14)
/// - QWERTY outputs: 'e'
/// - Colemak expects: 'f' at that position
/// - Generated mapping: `e -> f`
enum KeymapMappingGenerator {
    /// Generate key mappings to remap from QWERTY to the target layout.
    ///
    /// - Parameters:
    ///   - targetLayout: The layout to remap to (e.g., Colemak, Dvorak)
    ///   - includePunctuation: Whether to include punctuation key remappings
    /// - Returns: Array of KeyMapping objects, empty if target is QWERTY (no remapping needed)
    static func generateMappings(
        to targetLayout: LogicalKeymap,
        includePunctuation: Bool
    ) -> [KeyMapping] {
        // QWERTY is the identity mapping - no remapping needed
        guard targetLayout.id != LogicalKeymap.defaultId else {
            return []
        }

        let qwerty = LogicalKeymap.qwertyUS
        var mappings: [KeyMapping] = []

        // Process core letter block (30 keys: 3 rows x 10 keys)
        for (keyCode, qwertyLabel) in qwerty.coreLabels {
            guard let targetLabel = targetLayout.coreLabels[keyCode] else { continue }

            // Only create mapping if the key outputs something different
            if qwertyLabel != targetLabel {
                mappings.append(KeyMapping(
                    input: qwertyLabel,
                    output: targetLabel,
                    description: "Keymap: \(qwertyLabel) → \(targetLabel)"
                ))
            }
        }

        // Process punctuation if requested
        if includePunctuation {
            // Dvorak has significant punctuation remapping
            for (keyCode, targetLabel) in targetLayout.extraLabels {
                // Get what QWERTY outputs at this position
                guard let qwertyLabel = qwerty.extraLabels[keyCode] ?? punctuationForKeyCode(keyCode) else {
                    continue
                }

                if qwertyLabel != targetLabel {
                    mappings.append(KeyMapping(
                        input: qwertyLabel,
                        output: targetLabel,
                        description: "Keymap punctuation: \(qwertyLabel) → \(targetLabel)"
                    ))
                }
            }
        }

        return mappings
    }

    /// Get the QWERTY character for punctuation key codes
    private static func punctuationForKeyCode(_ keyCode: UInt16) -> String? {
        // Standard QWERTY punctuation positions
        let punctuationMap: [UInt16: String] = [
            50: "`",   // grave
            27: "-",   // minus
            24: "=",   // equal
            33: "[",   // left bracket
            30: "]",   // right bracket
            42: "\\",  // backslash
            39: "'"    // apostrophe
        ]
        return punctuationMap[keyCode]
    }

    /// Generate a RuleCollection containing the keymap remapping rules.
    ///
    /// This creates a managed collection that can be included in config generation.
    static func generateCollection(
        for keymapId: String,
        includePunctuation: Bool
    ) -> RuleCollection? {
        guard let keymap = LogicalKeymap.find(id: keymapId) else {
            return nil
        }

        // QWERTY doesn't need a collection
        guard keymapId != LogicalKeymap.defaultId else {
            return nil
        }

        let mappings = generateMappings(to: keymap, includePunctuation: includePunctuation)

        guard !mappings.isEmpty else {
            return nil
        }

        return RuleCollection(
            id: RuleCollectionIdentifier.keymapLayout,
            name: "\(keymap.name) Layout",
            summary: "Remaps physical QWERTY keys to \(keymap.name) layout.",
            category: .system,
            mappings: mappings,
            isEnabled: true,
            isSystemDefault: false,
            icon: "keyboard",
            targetLayer: .base
        )
    }
}

// MARK: - Identifier for Keymap Collection

extension RuleCollectionIdentifier {
    /// UUID for the keymap layout collection (stable across sessions)
    static let keymapLayout = UUID(uuidString: "AEE1A400-1A10-0000-0000-000000000000")!
}
