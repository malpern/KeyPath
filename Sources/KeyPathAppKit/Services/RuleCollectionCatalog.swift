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
        [macOSFunctionKeys, navigationArrows, windowManagement, capsLockRemap, escapeRemap, deleteRemap]
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
                KeyMapping(input: "f1", output: "brdn", description: "Brightness down"),
                KeyMapping(input: "f2", output: "brup", description: "Brightness up"),
                KeyMapping(input: "f7", output: "prev", description: "Previous track"),
                KeyMapping(input: "f8", output: "pp", description: "Play / Pause"),
                KeyMapping(input: "f9", output: "next", description: "Next track"),
                KeyMapping(input: "f10", output: "mute", description: "Mute"),
                KeyMapping(input: "f11", output: "vold", description: "Volume down"),
                KeyMapping(input: "f12", output: "volu", description: "Volume up")
            ],
            isEnabled: true,
            isSystemDefault: true,
            icon: "applelogo",
            targetLayer: .base,
            displayStyle: .table
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
            icon: "resource:vim-icon",
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
                KeyMapping(input: "C-M-A-up", output: "C-up", description: "Mission Control"),
                KeyMapping(input: "C-M-A-down", output: "C-down", description: "App Exposé"),
                KeyMapping(input: "C-M-A-left", output: "C-left", description: "Previous Desktop"),
                KeyMapping(input: "C-M-A-right", output: "C-right", description: "Next Desktop"),
                KeyMapping(input: "C-M-A-d", output: "f11", description: "Show Desktop"),
                KeyMapping(input: "C-M-A-n", output: "C-S-n", description: "Notification Center")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "rectangle.3.group",
            tags: ["mission control", "spaces", "desktop"],
            displayStyle: .table
        )
    }

    private var capsLockRemap: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.capsLockRemap,
            name: "Caps Lock",
            summary: "Remap Caps Lock to a more useful key",
            category: .productivity,
            mappings: [
                // Default mapping - will be updated based on selectedOutput
                KeyMapping(input: "caps", output: "f18", description: "Hyper key")
            ],
            isEnabled: true,
            isSystemDefault: true,
            icon: "capslock",
            tags: ["caps lock", "hyper", "escape", "control", "productivity"],
            displayStyle: .singleKeyPicker,
            pickerInputKey: "caps",
            presetOptions: [
                SingleKeyPreset(
                    output: "f18",
                    label: "✦ Hyper",
                    description: "F18 key for automation tools (Keyboard Maestro, Raycast, etc.)",
                    icon: "bolt.circle"
                ),
                SingleKeyPreset(
                    output: "esc",
                    label: "⎋ Escape",
                    description: "Popular for Vim users - quick access to Escape key",
                    icon: "escape"
                ),
                SingleKeyPreset(
                    output: "lctl",
                    label: "⌃ Control",
                    description: "Use Caps Lock as Control (common on Unix systems)",
                    icon: "control"
                ),
                SingleKeyPreset(
                    output: "bspc",
                    label: "⌫ Delete",
                    description: "Easy access to Delete without reaching",
                    icon: "delete.left"
                )
            ],
            selectedOutput: "f18"
        )
    }

    private var escapeRemap: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.escapeRemap,
            name: "Escape",
            summary: "Remap the Escape key",
            category: .productivity,
            mappings: [
                KeyMapping(input: "esc", output: "caps", description: "Caps Lock")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "escape",
            tags: ["escape", "caps lock", "swap"],
            displayStyle: .singleKeyPicker,
            pickerInputKey: "esc",
            presetOptions: [
                SingleKeyPreset(
                    output: "caps",
                    label: "⇪ Caps Lock",
                    description: "Swap Escape with Caps Lock (use with Caps Lock → Escape)",
                    icon: "capslock"
                ),
                SingleKeyPreset(
                    output: "grv",
                    label: "` Backtick",
                    description: "Remap Escape to backtick/grave accent",
                    icon: "character"
                ),
                SingleKeyPreset(
                    output: "tab",
                    label: "⇥ Tab",
                    description: "Remap Escape to Tab",
                    icon: "arrow.right.to.line"
                )
            ],
            selectedOutput: "caps"
        )
    }

    private var deleteRemap: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.deleteRemap,
            name: "Delete Enhancement",
            summary: "Leader + Delete for enhanced delete actions (regular Delete unchanged)",
            category: .productivity,
            mappings: [
                KeyMapping(input: "bspc", output: "del", description: "Forward Delete")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "delete.left",
            tags: ["delete", "backspace", "forward delete", "leader"],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .navigation),
            activationHint: "Hold Leader + Delete",
            displayStyle: .singleKeyPicker,
            pickerInputKey: "bspc",
            presetOptions: [
                SingleKeyPreset(
                    output: "del",
                    label: "⌦ Fwd Delete",
                    description: "Leader + Delete → Forward Delete (delete character after cursor)",
                    icon: "delete.right"
                ),
                SingleKeyPreset(
                    output: "A-bspc",
                    label: "⌥⌫ Del Word",
                    description: "Leader + Delete → Delete entire word",
                    icon: "text.word.spacing"
                ),
                SingleKeyPreset(
                    output: "M-bspc",
                    label: "⌘⌫ Del Line",
                    description: "Leader + Delete → Delete to beginning of line",
                    icon: "text.alignleft"
                )
            ],
            selectedOutput: "del"
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
