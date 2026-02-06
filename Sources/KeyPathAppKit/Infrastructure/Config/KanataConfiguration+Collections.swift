import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
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
                summary: "Preserves brightness, volume, and media control keys (F1-F12).",
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
        [
            KeyMapping(input: "f1", output: "brdn"),
            KeyMapping(input: "f2", output: "brup"),
            KeyMapping(input: "f3", output: "f3"),
            KeyMapping(input: "f4", output: "f4"),
            KeyMapping(input: "f7", output: "prev"),
            KeyMapping(input: "f8", output: "pp"),
            KeyMapping(input: "f9", output: "next"),
            KeyMapping(input: "f10", output: "mute"),
            KeyMapping(input: "f11", output: "vold"),
            KeyMapping(input: "f12", output: "volu")
        ]
    }
}
