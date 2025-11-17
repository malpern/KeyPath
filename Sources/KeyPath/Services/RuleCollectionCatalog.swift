import Foundation

/// Provides predefined rule collections that ship with the app.
struct RuleCollectionCatalog {
    func defaultCollections() -> [RuleCollection] {
        builtInList
    }

    func upgradedCollection(from existing: RuleCollection) -> RuleCollection {
        guard let updated = builtInCollections[existing.id] else { return existing }
        var merged = updated
        merged.isEnabled = existing.isEnabled
        return merged
    }

    // MARK: - Predefined collections

    private var builtInList: [RuleCollection] { [macOSFunctionKeys, navigationArrows] }

    private var builtInCollections: [UUID: RuleCollection] {
        Dictionary(uniqueKeysWithValues: builtInList.map { ($0.id, $0) })
    }

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
            icon: "keyboard",
            targetLayer: .base
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
            tags: ["vim", "navigation"],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation),
            activationHint: "Hold space to enter Navigation layer"
        )
    }
}
