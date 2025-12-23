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
        [macOSFunctionKeys, leaderKeyConfig, navigationArrows, missionControl, windowSnapping, capsLockRemap, backupCapsLock, escapeRemap, deleteRemap, homeRowMods, numpadLayer, symbolLayer]
    }

    private var builtInCollections: [UUID: RuleCollection] {
        Dictionary(uniqueKeysWithValues: builtInList.map { ($0.id, $0) })
    }

    private var macOSFunctionKeys: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.macFunctionKeys,
            name: "macOS Function Keys",
            summary: "Preserves brightness, volume, media, and system control keys (F1-F12).",
            category: .system,
            mappings: [
                KeyMapping(input: "f1", output: "brdn", description: "Brightness down"),
                KeyMapping(input: "f2", output: "brup", description: "Brightness up"),
                KeyMapping(input: "f3", output: #"(push-msg "system:mission-control")"#, description: "Mission Control"),
                KeyMapping(input: "f4", output: #"(push-msg "system:spotlight")"#, description: "Spotlight"),
                KeyMapping(input: "f5", output: #"(push-msg "system:dictation")"#, description: "Dictation"),
                KeyMapping(input: "f6", output: #"(push-msg "system:dnd")"#, description: "Do Not Disturb"),
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

    private var leaderKeyConfig: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.leaderKey,
            name: "Leader Key",
            summary: "Change the key that activates all layer shortcuts (Vim, Delete, etc.)",
            category: .system,
            mappings: [], // No direct mappings - this controls other collections' activators
            isEnabled: false,
            isSystemDefault: false,
            icon: "hand.point.up.left",
            tags: ["leader", "layer", "modifier", "navigation"],
            displayStyle: .singleKeyPicker,
            pickerInputKey: "leader",
            presetOptions: [
                SingleKeyPreset(
                    output: "space",
                    label: "␣ Space",
                    description: "Spacebar - most common, easy thumb access. Tap for space, hold for shortcuts.",
                    icon: "space"
                ),
                SingleKeyPreset(
                    output: "caps",
                    label: "⇪ Caps",
                    description: "Caps Lock - dedicated modifier key, no conflict with typing.",
                    icon: "capslock"
                ),
                SingleKeyPreset(
                    output: "tab",
                    label: "⇥ Tab",
                    description: "Tab key - left pinky access, tap for tab, hold for shortcuts.",
                    icon: "arrow.right.to.line"
                ),
                SingleKeyPreset(
                    output: "grv",
                    label: "` Grave",
                    description: "Backtick key - upper left corner, rarely used in normal typing.",
                    icon: "character"
                )
            ],
            selectedOutput: "space"
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
            summary: "Vim-style navigation and text editing. Hold Leader + hjkl for arrows. Add Shift for selection.",
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
            activationHint: "Hold Leader key to enter Navigation layer",
            displayStyle: .table
        )
    }

    private var missionControl: RuleCollection {
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

    // MARK: - Window Snapping

    /// Window snapping collection - activated via Leader → w → action keys
    ///
    /// ## Phase 2 TODO
    /// Add workspace/space movement (requires SkyLight framework or drag simulation).
    /// See Rectangle's implementation: https://github.com/rxhanson/Rectangle
    private var windowSnapping: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.windowSnapping,
            name: "Window Snapping",
            summary: "Snap windows to screen edges and corners. Leader → w → action key.",
            category: .productivity,
            mappings: [
                // Halves
                KeyMapping(input: "h", output: #"(push-msg "window:left")"#, description: "Left half"),
                KeyMapping(input: "l", output: #"(push-msg "window:right")"#, description: "Right half"),
                // Full/center
                KeyMapping(input: "m", output: #"(push-msg "window:maximize")"#, description: "Maximize/Restore"),
                KeyMapping(input: "c", output: #"(push-msg "window:center")"#, description: "Center"),
                // Corners (using vim-adjacent keys: y/u for top, b/n for bottom)
                KeyMapping(input: "y", output: #"(push-msg "window:top-left")"#, description: "Top-left", sectionBreak: true),
                KeyMapping(input: "u", output: #"(push-msg "window:top-right")"#, description: "Top-right"),
                KeyMapping(input: "b", output: #"(push-msg "window:bottom-left")"#, description: "Bottom-left"),
                KeyMapping(input: "n", output: #"(push-msg "window:bottom-right")"#, description: "Bottom-right"),
                // Display & undo
                KeyMapping(input: "[", output: #"(push-msg "window:previous-display")"#, description: "Previous display", sectionBreak: true),
                KeyMapping(input: "]", output: #"(push-msg "window:next-display")"#, description: "Next display"),
                KeyMapping(input: "z", output: #"(push-msg "window:undo")"#, description: "Undo")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "rectangle.split.2x2",
            tags: ["window", "snapping", "tiling", "rectangle", "display"],
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(
                input: "w",
                targetLayer: .custom("window"),
                sourceLayer: .navigation  // Activated from within navigation layer
            ),
            activationHint: "Leader → w → action key",
            displayStyle: .table
        )
    }

    private var capsLockRemap: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.capsLockRemap,
            name: "Caps Lock Remap",
            summary: "Make Caps Lock actually useful with tap and hold actions",
            category: .productivity,
            mappings: [
                // Mapping will be generated based on selectedTapOutput and selectedHoldOutput
                KeyMapping(
                    input: "caps",
                    output: "esc",
                    description: "Tap: Escape, Hold: Hyper",
                    behavior: .dualRole(
                        DualRoleBehavior(
                            tapAction: "esc",
                            holdAction: "hyper",
                            tapTimeout: 200,
                            holdTimeout: 200,
                            activateHoldOnOtherKey: false,
                            quickTap: false
                        )
                    )
                )
            ],
            isEnabled: true,
            isSystemDefault: true,
            icon: "capslock",
            tags: ["caps lock", "hyper", "escape", "control", "meh", "productivity", "tap-hold"],
            displayStyle: .tapHoldPicker,
            pickerInputKey: "caps",
            tapHoldOptions: TapHoldPresetOptions(
                tapOptions: [
                    SingleKeyPreset(
                        output: "esc",
                        label: "⎋ Escape",
                        description: "Popular for Vim users - quick access to Escape",
                        icon: "escape"
                    ),
                    SingleKeyPreset(
                        output: "caps",
                        label: "⇪ Caps Lock",
                        description: "Keep original Caps Lock function on tap",
                        icon: "capslock"
                    ),
                    SingleKeyPreset(
                        output: "bspc",
                        label: "⌫ Delete",
                        description: "Easy access to Delete without reaching",
                        icon: "delete.left"
                    ),
                    SingleKeyPreset(
                        output: "XX",
                        label: "None",
                        description: "No tap action - hold only",
                        icon: "minus.circle"
                    )
                ],
                holdOptions: [
                    SingleKeyPreset(
                        output: "hyper",
                        label: "✦ Hyper",
                        description: "All four modifiers (⌃⌥⇧⌘) - ultimate shortcut prefix",
                        icon: "bolt.circle"
                    ),
                    SingleKeyPreset(
                        output: "meh",
                        label: "◇ Meh",
                        description: "Three modifiers (⌃⌥⇧) - Hyper without Command",
                        icon: "diamond"
                    ),
                    SingleKeyPreset(
                        output: "lctl",
                        label: "⌃ Control",
                        description: "Control modifier (common on Unix systems)",
                        icon: "control"
                    ),
                    SingleKeyPreset(
                        output: "lsft",
                        label: "⇧ Shift",
                        description: "Shift modifier",
                        icon: "shift"
                    )
                ]
            ),
            selectedTapOutput: "esc",
            selectedHoldOutput: "hyper"
        )
    }

    private var backupCapsLock: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.backupCapsLock,
            name: "Backup Caps Lock",
            summary: "Alternative way to access Caps Lock (both Shift keys)",
            category: .productivity,
            mappings: [
                // Chord mapping: lsft + rsft = caps
                KeyMapping(input: "lsft rsft", output: "caps", description: "Both Shifts → Caps Lock")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "shift",
            tags: ["caps lock", "shift", "backup", "chord"],
            displayStyle: .singleKeyPicker,
            pickerInputKey: "backup-caps",
            presetOptions: [
                SingleKeyPreset(
                    output: "both-shifts",
                    label: "⇧⇧ Both Shifts",
                    description: "Press both Shift keys together to toggle Caps Lock",
                    icon: "shift"
                ),
                SingleKeyPreset(
                    output: "double-tap-esc",
                    label: "⎋⎋ Double-tap Esc",
                    description: "Double-tap Escape to toggle Caps Lock",
                    icon: "escape"
                )
            ],
            selectedOutput: "both-shifts"
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

    private var homeRowMods: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "Home row keys act as modifiers when held",
            category: .productivity,
            mappings: [], // Generated from homeRowModsConfig
            isEnabled: false,
            isSystemDefault: false,
            icon: "keyboard",
            tags: ["home row", "modifiers", "productivity", "ergonomics"],
            displayStyle: .homeRowMods,
            homeRowModsConfig: HomeRowModsConfig()
        )
    }

    // MARK: - Numpad Layer

    private var numpadLayer: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.numpadLayer,
            name: "Numpad Layer",
            summary: "Right hand becomes a numpad. Hold activator key + use U/I/O, J/K/L, M/,/. for 7-8-9, 4-5-6, 1-2-3.",
            category: .productivity,
            mappings: [
                // Right hand numpad (standard layout)
                KeyMapping(input: "u", output: "kp7", description: "7"),
                KeyMapping(input: "i", output: "kp8", description: "8"),
                KeyMapping(input: "o", output: "kp9", description: "9"),
                KeyMapping(input: "j", output: "kp4", description: "4"),
                KeyMapping(input: "k", output: "kp5", description: "5"),
                KeyMapping(input: "l", output: "kp6", description: "6"),
                KeyMapping(input: "m", output: "kp1", description: "1"),
                KeyMapping(input: ",", output: "kp2", description: "2"),
                KeyMapping(input: ".", output: "kp3", description: "3"),
                KeyMapping(input: "n", output: "kp0", description: "0"),
                KeyMapping(input: "/", output: "kp.", description: "."),
                // Left hand operators
                KeyMapping(input: "f", output: "kp+", description: "+", sectionBreak: true),
                KeyMapping(input: "d", output: "kp-", description: "−"),
                KeyMapping(input: "s", output: "kp*", description: "×"),
                KeyMapping(input: "a", output: "kp/", description: "÷"),
                KeyMapping(input: "g", output: "kprt", description: "⏎")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "number.square",
            tags: ["numpad", "numbers", "data entry", "calculator"],
            targetLayer: .custom("numpad"),
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .custom("numpad")),
            activationHint: "Hold Leader key to access numpad",
            displayStyle: .table
        )
    }

    // MARK: - Symbol Layer

    private var symbolLayer: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.symbolLayer,
            name: "Symbol Layer",
            summary: "Quick access to programming symbols. Choose a layout optimized for your workflow.",
            category: .productivity,
            mappings: [], // Generated from selected layer preset
            isEnabled: false,
            isSystemDefault: false,
            icon: "textformat.abc.dottedunderline",
            tags: ["symbols", "programming", "brackets", "operators"],
            targetLayer: .custom("sym"),
            momentaryActivator: MomentaryActivator(input: "space", targetLayer: .custom("sym")),
            activationHint: "Hold Leader key to access symbols",
            displayStyle: .layerPresetPicker,
            layerPresets: symbolLayerPresets,
            selectedLayerPreset: "mirrored"
        )
    }

    /// Symbol layer preset configurations
    private var symbolLayerPresets: [LayerPreset] {
        [
            LayerPreset(
                id: "mirrored",
                label: "Mirrored",
                description: "Symbols mirror number positions (1→!, 2→@). Easy to learn.",
                icon: "arrow.left.arrow.right",
                mappings: [
                    // Top row - shifted numbers in same positions
                    KeyMapping(input: "1", output: "S-1", description: "!"),
                    KeyMapping(input: "2", output: "S-2", description: "@"),
                    KeyMapping(input: "3", output: "S-3", description: "#"),
                    KeyMapping(input: "4", output: "S-4", description: "$"),
                    KeyMapping(input: "5", output: "S-5", description: "%"),
                    KeyMapping(input: "6", output: "S-6", description: "^"),
                    KeyMapping(input: "7", output: "S-7", description: "&"),
                    KeyMapping(input: "8", output: "S-8", description: "*"),
                    KeyMapping(input: "9", output: "S-9", description: "("),
                    KeyMapping(input: "0", output: "S-0", description: ")"),
                    // Home row - common operators
                    KeyMapping(input: "a", output: "S-grv", description: "~", sectionBreak: true),
                    KeyMapping(input: "s", output: "grv", description: "`"),
                    KeyMapping(input: "d", output: "min", description: "-"),
                    KeyMapping(input: "f", output: "eql", description: "="),
                    KeyMapping(input: "g", output: "S-eql", description: "+"),
                    KeyMapping(input: "h", output: "[", description: "["),
                    KeyMapping(input: "j", output: "]", description: "]"),
                    KeyMapping(input: "k", output: "S-[", description: "{"),
                    KeyMapping(input: "l", output: "S-]", description: "}"),
                    KeyMapping(input: ";", output: "S-\\", description: "|"),
                    // Bottom row - less common
                    KeyMapping(input: "z", output: "\\", description: "\\", sectionBreak: true),
                    KeyMapping(input: "x", output: "S-min", description: "_"),
                    KeyMapping(input: "c", output: "/", description: "/"),
                    KeyMapping(input: "v", output: "S-/", description: "?"),
                    KeyMapping(input: "b", output: "'", description: "'"),
                    KeyMapping(input: "n", output: "S-'", description: "\""),
                    KeyMapping(input: "m", output: "S-;", description: ":"),
                    KeyMapping(input: ",", output: "S-,", description: "<"),
                    KeyMapping(input: ".", output: "S-.", description: ">")
                ]
            ),
            LayerPreset(
                id: "paired",
                label: "Paired Brackets",
                description: "Opening brackets on left, closing on right. Visual symmetry.",
                icon: "curlybraces",
                mappings: [
                    // Left hand - opening brackets and operators
                    KeyMapping(input: "q", output: "S-grv", description: "~"),
                    KeyMapping(input: "w", output: "S-1", description: "!"),
                    KeyMapping(input: "e", output: "S-2", description: "@"),
                    KeyMapping(input: "r", output: "S-3", description: "#"),
                    KeyMapping(input: "t", output: "S-4", description: "$"),
                    KeyMapping(input: "a", output: "S-[", description: "{", sectionBreak: true),
                    KeyMapping(input: "s", output: "S-9", description: "("),
                    KeyMapping(input: "d", output: "[", description: "["),
                    KeyMapping(input: "f", output: "S-,", description: "<"),
                    KeyMapping(input: "g", output: "min", description: "-"),
                    KeyMapping(input: "z", output: "S-\\", description: "|", sectionBreak: true),
                    KeyMapping(input: "x", output: "S-eql", description: "+"),
                    KeyMapping(input: "c", output: "S-min", description: "_"),
                    KeyMapping(input: "v", output: "/", description: "/"),
                    KeyMapping(input: "b", output: "\\", description: "\\"),
                    // Right hand - closing brackets and symbols
                    KeyMapping(input: "y", output: "S-5", description: "%", sectionBreak: true),
                    KeyMapping(input: "u", output: "S-6", description: "^"),
                    KeyMapping(input: "i", output: "S-7", description: "&"),
                    KeyMapping(input: "o", output: "S-8", description: "*"),
                    KeyMapping(input: "p", output: "grv", description: "`"),
                    KeyMapping(input: "h", output: "eql", description: "=", sectionBreak: true),
                    KeyMapping(input: "j", output: "S-.", description: ">"),
                    KeyMapping(input: "k", output: "]", description: "]"),
                    KeyMapping(input: "l", output: "S-0", description: ")"),
                    KeyMapping(input: ";", output: "S-]", description: "}"),
                    KeyMapping(input: "n", output: "S-/", description: "?", sectionBreak: true),
                    KeyMapping(input: "m", output: "S-;", description: ":"),
                    KeyMapping(input: ",", output: ";", description: ";"),
                    KeyMapping(input: ".", output: "'", description: "'"),
                    KeyMapping(input: "/", output: "S-'", description: "\"")
                ]
            ),
            LayerPreset(
                id: "programmer",
                label: "Programmer",
                description: "Common bigrams (→, !=, <=) as comfortable rolls. Optimized for coding.",
                icon: "chevron.left.forwardslash.chevron.right",
                mappings: [
                    // Top row - numbers as-is for easy access
                    KeyMapping(input: "q", output: "S-1", description: "!"),
                    KeyMapping(input: "w", output: "S-2", description: "@"),
                    KeyMapping(input: "e", output: "S-3", description: "#"),
                    KeyMapping(input: "r", output: "S-4", description: "$"),
                    KeyMapping(input: "t", output: "S-5", description: "%"),
                    KeyMapping(input: "y", output: "S-6", description: "^"),
                    KeyMapping(input: "u", output: "S-7", description: "&"),
                    KeyMapping(input: "i", output: "S-8", description: "*"),
                    KeyMapping(input: "o", output: "S-grv", description: "~"),
                    KeyMapping(input: "p", output: "grv", description: "`"),
                    // Home row - brackets optimized for -> <= != bigrams
                    KeyMapping(input: "a", output: "S-[", description: "{", sectionBreak: true),
                    KeyMapping(input: "s", output: "S-9", description: "("),
                    KeyMapping(input: "d", output: "[", description: "["),
                    KeyMapping(input: "f", output: "S-,", description: "<"),
                    KeyMapping(input: "g", output: "eql", description: "="),
                    KeyMapping(input: "h", output: "min", description: "-"),
                    KeyMapping(input: "j", output: "S-.", description: ">"),
                    KeyMapping(input: "k", output: "]", description: "]"),
                    KeyMapping(input: "l", output: "S-0", description: ")"),
                    KeyMapping(input: ";", output: "S-]", description: "}"),
                    // Bottom row - less common symbols
                    KeyMapping(input: "z", output: "S-\\", description: "|", sectionBreak: true),
                    KeyMapping(input: "x", output: "S-eql", description: "+"),
                    KeyMapping(input: "c", output: "S-min", description: "_"),
                    KeyMapping(input: "v", output: "S-/", description: "?"),
                    KeyMapping(input: "b", output: "\\", description: "\\"),
                    KeyMapping(input: "n", output: "/", description: "/"),
                    KeyMapping(input: "m", output: "S-;", description: ":"),
                    KeyMapping(input: ",", output: ";", description: ";"),
                    KeyMapping(input: ".", output: "'", description: "'"),
                    KeyMapping(input: "/", output: "S-'", description: "\"")
                ]
            )
        ]
    }
}
