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
            KeyMapping(input: "f1", action: .keystroke(key: "brdn")),
            KeyMapping(input: "f2", action: .keystroke(key: "brup")),
            KeyMapping(input: "f3", action: .keystroke(key: "f3")),
            KeyMapping(input: "f4", action: .keystroke(key: "f4")),
            KeyMapping(input: "f7", action: .keystroke(key: "prev")),
            KeyMapping(input: "f8", action: .keystroke(key: "pp")),
            KeyMapping(input: "f9", action: .keystroke(key: "next")),
            KeyMapping(input: "f10", action: .keystroke(key: "mute")),
            KeyMapping(input: "f11", action: .keystroke(key: "vold")),
            KeyMapping(input: "f12", action: .keystroke(key: "volu"))
        ]
    }
}
