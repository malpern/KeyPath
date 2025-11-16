import Foundation

/// Provides predefined rule collections that ship with the app.
struct RuleCollectionCatalog {
    func defaultCollections() -> [RuleCollection] {
        [macOSFunctionKeys, navigationArrows]
    }

    // MARK: - Predefined collections

    private var macOSFunctionKeys: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.macFunctionKeys,
            name: "macOS Function Keys",
            summary: "Preserves brightness, volume, and media control keys (F1-F12).",
            category: .system,
            mappings: [
                KeyMapping(input: "f1", output: "brdn"),
                KeyMapping(input: "f2", output: "brup"),
                KeyMapping(input: "f7", output: "prev"),
                KeyMapping(input: "f8", output: "pp"),
                KeyMapping(input: "f9", output: "next"),
                KeyMapping(input: "f10", output: "mute"),
                KeyMapping(input: "f11", output: "vold"),
                KeyMapping(input: "f12", output: "volu")
            ],
            isEnabled: true,
            isSystemDefault: true,
            icon: "keyboard"
        )
    }

    private var navigationArrows: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.vimNavigation,
            name: "Vim Navigation",
            summary: "Use H/J/K/L for arrow navigation (example preset).",
            category: .navigation,
            mappings: [
                KeyMapping(input: "h", output: "left"),
                KeyMapping(input: "j", output: "down"),
                KeyMapping(input: "k", output: "up"),
                KeyMapping(input: "l", output: "right")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "arrow.up.and.down.and.arrow.left.and.right",
            tags: ["vim", "navigation"]
        )
    }
}
