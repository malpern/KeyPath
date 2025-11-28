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
        [macOSFunctionKeys, navigationArrows, windowManagement, capsLockHyperKey, capsLockEscape]
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

    // Kanata modifier key reference (for Mac):
    // M- = Meta = ⌘ Command (lmet/rmet)
    // A- = Alt  = ⌥ Option  (lalt/ralt)
    // C- = Ctrl = ⌃ Control (lctl/rctl)
    // S- = Shift = ⇧ Shift  (lsft/rsft)

    private var navigationArrows: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.vimNavigation,
            name: "Vim",
            summary: "Vim-style navigation and text editing. Hold Space + hjkl for arrows. Add Shift for selection.",
            category: .navigation,
            mappings: [
                // === Basic navigation (hjkl) ===
                KeyMapping(input: "h", output: "left", description: "Move left"),
                KeyMapping(input: "j", output: "down", description: "Move down"),
                KeyMapping(input: "k", output: "up", description: "Move up"),
                KeyMapping(input: "l", output: "right", description: "Move right"),

                // === Word navigation ===
                KeyMapping(input: "w", output: "A-right", description: "Word forward"),
                KeyMapping(input: "b", output: "A-left", description: "Word backward"),
                KeyMapping(input: "e", output: "A-right", description: "End of word"),

                // === Line navigation ===
                KeyMapping(input: "0", output: "M-left", description: "Line start"),
                KeyMapping(input: "4", output: "M-right", description: "Line end ($)"),
                KeyMapping(input: "a", output: "right", shiftedOutput: "M-right", description: "Append / End of line"),

                // === Document navigation ===
                KeyMapping(input: "g", output: "M-up", shiftedOutput: "M-down", description: "Doc start / Doc end"),

                // === Search ===
                KeyMapping(input: "/", output: "M-f", description: "Find", sectionBreak: true),
                KeyMapping(input: "n", output: "M-g", shiftedOutput: "M-S-g", description: "Next match / Prev match"),

                // === Copy/paste ===
                KeyMapping(input: "y", output: "M-c", description: "Yank (copy)"),
                KeyMapping(input: "p", output: "M-v", description: "Put (paste)"),

                // === Editing ===
                KeyMapping(input: "x", output: "del", description: "Delete char"),
                KeyMapping(input: "r", output: "M-S-z", description: "Redo"),
                KeyMapping(input: "d", output: "A-bspc", ctrlOutput: "pgdn", description: "Delete word / Page down"),
                KeyMapping(input: "u", output: "M-z", ctrlOutput: "pgup", description: "Undo / Page up"),

                // === Line operations ===
                KeyMapping(input: "o", output: "M-right ret", shiftedOutput: "up M-right ret", description: "Open line below / above")
            ],
            isEnabled: true,
            isSystemDefault: true,
            icon: "text:VIM",
            tags: ["vim", "navigation", "editing", "selection"],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation),
            activationHint: "Hold space to enter Navigation layer",
            displayStyle: .table
        )
    }

    private var windowManagement: RuleCollection {
        RuleCollection(
            id: UUID(uuidString: "C3A5E2F1-8D4B-4C9A-A1E7-5F3D9B2C8A6E")!,
            name: "Mission Control",
            summary: "Quick access to Mission Control, App Exposé, and Desktop switching.",
            category: .navigation,
            mappings: [
                KeyMapping(input: "C-M-A-up", output: "C-up"), // Mission Control
                KeyMapping(input: "C-M-A-down", output: "C-down"), // App Exposé
                KeyMapping(input: "C-M-A-left", output: "C-left"), // Previous Desktop
                KeyMapping(input: "C-M-A-right", output: "C-right"), // Next Desktop
                KeyMapping(input: "C-M-A-d", output: "f11"), // Show Desktop
                KeyMapping(input: "C-M-A-n", output: "C-S-n") // Notification Center
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "rectangle.3.group",
            tags: ["mission control", "spaces", "desktop"]
        )
    }

    private var capsLockHyperKey: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.capsLockHyperKey,
            name: "Caps Lock → Hyper Key",
            summary: "Remap Caps Lock to F18 for use as a unique trigger in automation tools.",
            category: .productivity,
            mappings: [
                KeyMapping(input: "caps", output: "f18")
            ],
            isEnabled: true,
            isSystemDefault: true,
            icon: "command.circle",
            tags: ["hyper", "productivity", "automation", "keyboard maestro", "bettertouchtool"]
        )
    }

    private var capsLockEscape: RuleCollection {
        RuleCollection(
            id: UUID(uuidString: "E5C7D4B3-AF6D-4E2C-C3C9-7B5F2D4E8A1C")!,
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

    // Note: Home row mods require tap-hold configuration which is not yet supported
    // by the simple KeyMapping model. This would need to be implemented as a
    // custom Kanata configuration block with defalias and tap-hold syntax.
    // Keeping this commented out until tap-hold support is added.
    //
    // private var homeRowMods: RuleCollection {
    //     RuleCollection(
    //         id: UUID(uuidString: "A7B9C5D1-6E8F-4A2B-9C3D-5E7F1A2B3C4D")!,
    //         name: "Home Row Mods",
    //         summary: "Hold home row keys (A, S, D, F, J, K, L, ;) for modifiers (Ctrl, Opt, Cmd, Shift).",
    //         category: .advanced,
    //         mappings: [], // Would require tap-hold implementation
    //         isEnabled: false,
    //         isSystemDefault: false,
    //         icon: "hand.point.up.left",
    //         tags: ["home row", "modifiers", "advanced", "ergonomic"],
    //         targetLayer: .base
    //     )
    // }
}
