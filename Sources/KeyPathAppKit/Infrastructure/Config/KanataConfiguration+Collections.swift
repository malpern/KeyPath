import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathRulesCore
import Network

extension KanataConfiguration {
    /// Get the system default collections (macOS Function Keys enabled by default)
    public static var systemDefaultCollections: [RuleCollection] {
        defaultSystemCollections
    }

    static var defaultSystemCollections: [RuleCollection] {
        [
            RuleCollection(
                id: RuleCollectionIdentifier.macFunctionKeys,
                name: "macOS Function Keys",
                summary: "Preserves standard function keys (F1-F12).",
                category: .system,
                mappings: macFunctionKeyMappings,
                isEnabled: true,
                isSystemDefault: true,
                icon: "keyboard",
                targetLayer: .base
            )
        ]
    }

    static var macFunctionKeyMappings: [KeyMapping] {
        // Automatic defaults must not introduce consumer output into a profile.
        RuleCollectionCatalog.functionKeyMappings(for: .function)
    }
}
