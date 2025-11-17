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

    private var builtInList: [RuleCollection] {
        [macOSFunctionKeys, navigationArrows, windowManagement, textEditing, capsLockEscape]
    }

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
            icon: "applelogo",
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
            icon: "text:VIM",
            tags: ["vim", "navigation"],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation),
            activationHint: "Hold space to enter Navigation layer"
        )
    }

    private var windowManagement: RuleCollection {
        RuleCollection(
            id: UUID(uuidString: "C3A5E2F1-8D4B-4C9A-A1E7-5F3D9B2C8A6E")!,
            name: "Mission Control",
            summary: "Quick access to Mission Control, App Exposé, and Desktop switching.",
            category: .navigation,
            mappings: [
                KeyMapping(input: "C-M-A-up", output: "C-up"),        // Mission Control
                KeyMapping(input: "C-M-A-down", output: "C-down"),    // App Exposé
                KeyMapping(input: "C-M-A-left", output: "C-left"),    // Previous Desktop
                KeyMapping(input: "C-M-A-right", output: "C-right"),  // Next Desktop
                KeyMapping(input: "C-M-A-d", output: "f11"),          // Show Desktop
                KeyMapping(input: "C-M-A-n", output: "C-S-n")         // Notification Center
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "rectangle.3.group",
            tags: ["mission control", "spaces", "desktop"]
        )
    }

    private var textEditing: RuleCollection {
        RuleCollection(
            id: UUID(uuidString: "D4B6F3A2-9E5C-4D1B-B2F8-6A4E1C3D7B9F")!,
            name: "Text Editing Layer",
            summary: "Enhanced text navigation and editing (hold Caps Lock).",
            category: .navigation,
            mappings: [
                KeyMapping(input: "h", output: "left"),
                KeyMapping(input: "j", output: "down"),
                KeyMapping(input: "k", output: "up"),
                KeyMapping(input: "l", output: "right"),
                KeyMapping(input: "w", output: "M-right"),      // Word forward
                KeyMapping(input: "b", output: "M-left"),       // Word backward
                KeyMapping(input: "0", output: "C-a"),          // Line start
                KeyMapping(input: "4", output: "C-e"),          // Line end
                KeyMapping(input: "d", output: "M-bspc"),       // Delete word
                KeyMapping(input: "u", output: "C-z"),          // Undo
                KeyMapping(input: "r", output: "C-S-z")         // Redo
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "text.cursor",
            tags: ["editing", "vim", "text"],
            targetLayer: .custom("editing"),
            momentaryActivator: MomentaryActivator(input: "caps", targetLayer: .custom("editing")),
            activationHint: "Hold Caps Lock to enter Editing layer"
        )
    }

    private var capsLockEscape: RuleCollection {
        RuleCollection(
            id: UUID(uuidString: "E5C7D4B3-AF6D-4E2C-C3G9-7B5F2D4E8A1C")!,
            name: "Caps Lock → Escape",
            summary: "Remap Caps Lock to Escape (popular for Vim users).",
            category: .system,
            mappings: [
                KeyMapping(input: "caps", output: "esc")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "capslock",
            tags: ["vim", "productivity", "escape"]
        )
    }
}
