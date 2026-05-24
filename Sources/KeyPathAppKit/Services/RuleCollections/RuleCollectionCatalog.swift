import Foundation

/// Provides predefined rule collections that ship with the app.
struct RuleCollectionCatalog {
    func defaultCollections() -> [RuleCollection] {
        builtInList
    }

    /// Returns the launcher collection (managed separately via overlay drawer)
    func launcherCollection() -> RuleCollection {
        launcher
    }

    func upgradedCollection(from existing: RuleCollection) -> RuleCollection {
        guard let updated = builtInCollections[existing.id] else { return existing }
        var merged = updated
        merged.isEnabled = existing.isEnabled
        // Preserve user's configuration for configurable collections
        // (e.g., launcher mappings, home row mods settings, etc.)
        // Only if the configuration type matches - otherwise use catalog default
        if existing.configuration.displayStyle == updated.configuration.displayStyle {
            // For tapHoldPicker: preserve user's selections but use catalog's options
            // This ensures removed options (like "None") don't persist
            if case let .tapHoldPicker(existingConfig) = existing.configuration,
               case let .tapHoldPicker(catalogConfig) = updated.configuration
            {
                var mergedConfig = catalogConfig
                // Preserve user's selection only if it's still a valid option
                if let selectedTap = existingConfig.selectedTapOutput,
                   catalogConfig.tapOptions.contains(where: { $0.output == selectedTap })
                {
                    mergedConfig.selectedTapOutput = selectedTap
                }
                if let selectedHold = existingConfig.selectedHoldOutput,
                   catalogConfig.holdOptions.contains(where: { $0.output == selectedHold })
                {
                    mergedConfig.selectedHoldOutput = selectedHold
                }
                merged.configuration = .tapHoldPicker(mergedConfig)
            } else {
                merged.configuration = existing.configuration
            }
        }
        return merged
    }

    // MARK: - Predefined collections

    private var builtInList: [RuleCollection] {
        [
            macOSFunctionKeys,
            leaderKeyConfig,
            navigationArrows,
            // KindaVim used to ship as a rule collection (raw kanata h/j/k/l
            // remappings). It is now a visual-only pack (no kanata bindings)
            // since kindaVim.app handles every keypress directly.
            neovimTerminal,
            missionControl,
            windowSnapping,
            capsLockRemap,
            backupCapsLock,
            escapeRemap,
            deleteRemap,
            homeRowMods,
            homeRowLayerToggles,
            chordGroups,
            sequences,
            numpadLayer,
            symbolLayer,
            funLayer,
            autoShiftSymbols,
            keyRepeatControl,
            homeRowArrows,
            vallackNavigation,
            launcher
        ]
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
                KeyMapping(input: "f1", action: .keystroke(key: "brdn"), description: "Brightness down"),
                KeyMapping(input: "f2", action: .keystroke(key: "brup"), description: "Brightness up"),
                KeyMapping(input: "f3", action: .rawKanata(#"(push-msg "system:mission-control")"#), description: "Mission Control"),
                KeyMapping(input: "f4", action: .rawKanata(#"(push-msg "system:spotlight")"#), description: "Spotlight"),
                KeyMapping(input: "f5", action: .rawKanata(#"(push-msg "system:dictation")"#), description: "Dictation"),
                KeyMapping(input: "f6", action: .rawKanata(#"(push-msg "system:dnd")"#), description: "Do Not Disturb"),
                KeyMapping(input: "f7", action: .keystroke(key: "prev"), description: "Previous track"),
                KeyMapping(input: "f8", action: .keystroke(key: "pp"), description: "Play / Pause"),
                KeyMapping(input: "f9", action: .keystroke(key: "next"), description: "Next track"),
                KeyMapping(input: "f10", action: .keystroke(key: "mute"), description: "Mute"),
                KeyMapping(input: "f11", action: .keystroke(key: "vold"), description: "Volume down"),
                KeyMapping(input: "f12", action: .keystroke(key: "volu"), description: "Volume up")
            ],
            isEnabled: true,
            isSystemDefault: true,
            icon: "applelogo",
            targetLayer: .base,
            configuration: .table
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
            configuration: .singleKeyPicker(SingleKeyPickerConfig(
                inputKey: "leader",
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
            ))
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
            name: "Vim - Apple Keyboard Shortcuts",
            summary: "Access familiar macOS shortcuts using Vim keys. Hold Leader + hjkl for arrows, y/p for copy/paste, u for undo, and more.",
            category: .navigation,
            mappings: [
                // === Basic navigation (hjkl) ===
                KeyMapping(input: "h", action: .keystroke(key: "left"), description: "h — left"),
                KeyMapping(input: "j", action: .keystroke(key: "down"), description: "j — down"),
                KeyMapping(input: "k", action: .keystroke(key: "up"), description: "k — up"),
                KeyMapping(input: "l", action: .keystroke(key: "right"), description: "l — right"),

                // === Line navigation ===
                KeyMapping(input: "0", action: .keystroke(key: "M-left"), description: "0 — line start"),
                KeyMapping(input: "4", action: .keystroke(key: "M-right"), description: "$ — line end"),
                KeyMapping(input: "a", action: .keystroke(key: "right"), shiftedOutput: "M-right", description: "a — append"),

                // === Document navigation ===
                KeyMapping(input: "g", action: .keystroke(key: "M-up"), shiftedOutput: "M-down", description: "gg / G — doc top/bottom"),

                // === Search ===
                KeyMapping(input: "/", action: .keystroke(key: "M-f"), description: "/ — find", sectionBreak: true),
                KeyMapping(input: "n", action: .keystroke(key: "M-g"), shiftedOutput: "M-S-g", description: "n / N — next/prev match"),

                // === Copy/paste ===
                KeyMapping(input: "y", action: .keystroke(key: "M-c"), description: "y — yank"),
                KeyMapping(input: "p", action: .keystroke(key: "M-v"), description: "p — put"),

                // === Editing ===
                KeyMapping(input: "x", action: .keystroke(key: "del"), description: "x — delete char"),
                KeyMapping(input: "r", action: .keystroke(key: "M-S-z"), description: "r — redo"),
                KeyMapping(input: "d", action: .keystroke(key: "A-bspc"), ctrlOutput: "pgdn", description: "d — delete previous word"),
                KeyMapping(input: "u", action: .keystroke(key: "M-z"), ctrlOutput: "pgup", description: "u — undo"),

                // === Line operations ===
                KeyMapping(input: "o", action: .keystroke(key: "M-right ret"), shiftedOutput: "up M-right ret", description: "o / O — open line below/above")
            ],
            isEnabled: true,
            isSystemDefault: true,
            icon: "resource:vim-icon",
            tags: ["vim", "navigation", "editing", "selection"],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(
                input: "space",
                targetLayer: .navigation
            ),
            activationHint: "Hold Leader key to enter Navigation layer",
            configuration: .table
        )
    }

    private var neovimTerminal: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.neovimTerminal,
            name: "Neovim Terminal",
            summary: "App-specific Neovim reference for approved terminal apps. It can run alongside other Navigation rules.",
            category: .navigation,
            mappings: [
                // === Basic navigation (hjkl) ===
                KeyMapping(input: "h", action: .keystroke(key: "left"), description: "h — left"),
                KeyMapping(input: "j", action: .keystroke(key: "down"), description: "j — down"),
                KeyMapping(input: "k", action: .keystroke(key: "up"), description: "k — up"),
                KeyMapping(input: "l", action: .keystroke(key: "right"), description: "l — right"),

                // === Word motions ===
                KeyMapping(input: "w", action: .keystroke(key: "A-right"), description: "w — word forward", sectionBreak: true),
                KeyMapping(input: "b", action: .keystroke(key: "A-left"), description: "b — word back"),
                KeyMapping(input: "e", action: .keystroke(key: "A-right"), description: "e — end of word"),

                // === Line navigation ===
                KeyMapping(input: "0", action: .keystroke(key: "M-left"), description: "0 — line start"),
                KeyMapping(input: "4", action: .keystroke(key: "M-right"), description: "$ — line end"),

                // === Document navigation ===
                KeyMapping(input: "g", action: .keystroke(key: "M-up"), shiftedOutput: "M-down", description: "gg / G — doc top/bottom"),

                // === Search ===
                KeyMapping(input: "/", action: .keystroke(key: "M-f"), description: "/ — find", sectionBreak: true),
                KeyMapping(input: "n", action: .keystroke(key: "M-g"), shiftedOutput: "M-S-g", description: "n / N — next/prev match"),

                // === Copy/paste ===
                KeyMapping(input: "y", action: .keystroke(key: "M-c"), description: "y — yank"),
                KeyMapping(input: "p", action: .keystroke(key: "M-v"), description: "p — put"),

                // === Editing ===
                KeyMapping(input: "x", action: .keystroke(key: "del"), description: "x — delete char"),
                KeyMapping(input: "r", action: .keystroke(key: "M-S-z"), description: "r — redo"),
                KeyMapping(input: "d", action: .keystroke(key: "A-bspc"), ctrlOutput: "pgdn", description: "d — delete previous word"),
                KeyMapping(input: "u", action: .keystroke(key: "M-z"), ctrlOutput: "pgup", description: "u — undo"),

                // === Line operations ===
                KeyMapping(input: "o", action: .keystroke(key: "M-right ret"), shiftedOutput: "up M-right ret", description: "o / O — open line below/above")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "terminal",
            tags: ["neovim", "vim", "terminal", "lsp", "telescope", "buffers"],
            targetLayer: .navigation,
            momentaryActivator: MomentaryActivator(
                input: "space",
                targetLayer: .navigation
            ),
            activationHint: "Hold Leader key to enter Navigation layer",
            configuration: .table
        )
    }

    private var missionControl: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.missionControl,
            name: "Mission Control",
            summary: "Leader → single key: Mission Control, Exposé, Desktops, Notification Center.",
            category: .navigation,
            // Maps onto uncommon keys inside the navigation layer so users
            // can hit Mission Control actions as Leader (Space) + single
            // letter — much cheaper than the previous 3-modifier chord form
            // and consistent with the rest of the Gallery (Vim Nav, Numpad,
            // Window Snapping all share the Leader → key pattern).
            //
            // Keys chosen to avoid colliding with BOTH Vim Navigation AND
            // KindaVim nav-layer bindings (both pack types share Space →
            // nav; a user can have either enabled). Safe unclaimed keys:
            // `q t c v m , .` — picked for mnemonic fit where possible.
            mappings: [
                KeyMapping(input: "m", action: .keystroke(key: "C-up"), description: "Mission Control"),
                KeyMapping(input: "q", action: .keystroke(key: "C-down"), description: "App Exposé"),
                KeyMapping(input: "t", action: .keystroke(key: "f11"), description: "Show Desktop"),
                KeyMapping(input: "c", action: .keystroke(key: "C-S-n"), description: "Notification Center"),
                KeyMapping(input: ",", action: .keystroke(key: "C-left"), description: "Previous Desktop"),
                KeyMapping(input: ".", action: .keystroke(key: "C-right"), description: "Next Desktop")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "rectangle.3.group",
            tags: ["mission control", "spaces", "desktop"],
            // Additive nav-layer pack — piggybacks on whichever nav
            // provider the user has enabled (Vim Navigation, KindaVim, or
            // Neovim Terminal). Doesn't declare its own Space activator
            // because that would collide with the nav provider's.
            targetLayer: .navigation,
            activationHint: "Leader → single key",
            configuration: .table
        )
    }

    // MARK: - Window Snapping

    /// Window snapping collection - activated via Leader → w → action keys
    ///
    /// Uses Accessibility API for window positioning and private CGS APIs for Space movement.
    /// See `WindowManager.swift` and `CGSPrivate.swift` for implementation details.
    private var windowSnapping: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.windowSnapping,
            name: "Window Snapping",
            summary: "Snap windows to edges/corners, move between displays and Spaces.",
            category: .productivity,
            mappings: Self.windowMappings(for: .standard),
            isEnabled: false,
            isSystemDefault: false,
            icon: "rectangle.split.2x2",
            tags: ["window", "snapping", "tiling", "rectangle", "display", "spaces"],
            targetLayer: .custom("window"),
            momentaryActivator: MomentaryActivator(
                input: "w",
                targetLayer: .custom("window"),
                sourceLayer: .navigation // Activated from within navigation layer
            ),
            activationHint: "Leader → w → action key",
            configuration: .table,
            windowKeyConvention: .standard
        )
    }

    /// Generate window snapping key mappings for a given convention
    static func windowMappings(for convention: WindowKeyConvention) -> [KeyMapping] {
        switch convention {
        case .standard:
            // Mnemonic keys: L=Left, R=Right, U/I/J/K spatial grid for corners
            [
                // Halves (mnemonic)
                KeyMapping(input: "l", action: .rawKanata(#"(push-msg "window:left")"#), description: "Left half"),
                KeyMapping(input: "r", action: .rawKanata(#"(push-msg "window:right")"#), description: "Right half"),
                // Full/center (mnemonic)
                KeyMapping(input: "m", action: .rawKanata(#"(push-msg "window:maximize")"#), description: "Maximize/Restore"),
                KeyMapping(input: "c", action: .rawKanata(#"(push-msg "window:center")"#), description: "Center"),
                // Corners (U/I/J/K spatial grid mirrors screen quadrants)
                KeyMapping(input: "u", action: .rawKanata(#"(push-msg "window:top-left")"#), description: "Top-left", sectionBreak: true),
                KeyMapping(input: "i", action: .rawKanata(#"(push-msg "window:top-right")"#), description: "Top-right"),
                KeyMapping(input: "j", action: .rawKanata(#"(push-msg "window:bottom-left")"#), description: "Bottom-left"),
                KeyMapping(input: "k", action: .rawKanata(#"(push-msg "window:bottom-right")"#), description: "Bottom-right"),
                // Display movement
                KeyMapping(input: "[", action: .rawKanata(#"(push-msg "window:previous-display")"#), description: "Previous display", sectionBreak: true),
                KeyMapping(input: "]", action: .rawKanata(#"(push-msg "window:next-display")"#), description: "Next display"),
                // Space movement (< > direction via , .)
                KeyMapping(input: ",", action: .rawKanata(#"(push-msg "window:previous-space")"#), description: "Previous Space", sectionBreak: true),
                KeyMapping(input: ".", action: .rawKanata(#"(push-msg "window:next-space")"#), description: "Next Space"),
                // Undo
                KeyMapping(input: "z", action: .rawKanata(#"(push-msg "window:undo")"#), description: "Undo", sectionBreak: true)
            ]
        case .vim:
            // Vim-style: H/L for left/right, Y/U/B/N for corners
            [
                // Halves (vim navigation)
                KeyMapping(input: "h", action: .rawKanata(#"(push-msg "window:left")"#), description: "Left half"),
                KeyMapping(input: "l", action: .rawKanata(#"(push-msg "window:right")"#), description: "Right half"),
                // Full/center
                KeyMapping(input: "m", action: .rawKanata(#"(push-msg "window:maximize")"#), description: "Maximize/Restore"),
                KeyMapping(input: "c", action: .rawKanata(#"(push-msg "window:center")"#), description: "Center"),
                // Corners (vim-adjacent keys: y/u for top, b/n for bottom)
                KeyMapping(input: "y", action: .rawKanata(#"(push-msg "window:top-left")"#), description: "Top-left", sectionBreak: true),
                KeyMapping(input: "u", action: .rawKanata(#"(push-msg "window:top-right")"#), description: "Top-right"),
                KeyMapping(input: "b", action: .rawKanata(#"(push-msg "window:bottom-left")"#), description: "Bottom-left"),
                KeyMapping(input: "n", action: .rawKanata(#"(push-msg "window:bottom-right")"#), description: "Bottom-right"),
                // Display movement
                KeyMapping(input: "[", action: .rawKanata(#"(push-msg "window:previous-display")"#), description: "Previous display", sectionBreak: true),
                KeyMapping(input: "]", action: .rawKanata(#"(push-msg "window:next-display")"#), description: "Next display"),
                // Space movement
                KeyMapping(input: "a", action: .rawKanata(#"(push-msg "window:previous-space")"#), description: "Previous Space", sectionBreak: true),
                KeyMapping(input: "s", action: .rawKanata(#"(push-msg "window:next-space")"#), description: "Next Space"),
                // Undo
                KeyMapping(input: "z", action: .rawKanata(#"(push-msg "window:undo")"#), description: "Undo", sectionBreak: true)
            ]
        }
    }

    /// Generate function key mappings for a given mode
    /// - Parameter mode: Media keys (default Mac behavior) or standard F-keys
    /// - Returns: Key mappings for F1-F12
    static func functionKeyMappings(for mode: FunctionKeyMode) -> [KeyMapping] {
        switch mode {
        case .media:
            // Default Mac behavior: F1-F12 send media/system commands
            [
                KeyMapping(input: "f1", action: .keystroke(key: "brdn"), description: "Brightness down"),
                KeyMapping(input: "f2", action: .keystroke(key: "brup"), description: "Brightness up"),
                KeyMapping(input: "f3", action: .rawKanata(#"(push-msg "system:mission-control")"#), description: "Mission Control"),
                KeyMapping(input: "f4", action: .rawKanata(#"(push-msg "system:spotlight")"#), description: "Spotlight"),
                KeyMapping(input: "f5", action: .rawKanata(#"(push-msg "system:dictation")"#), description: "Dictation"),
                KeyMapping(input: "f6", action: .rawKanata(#"(push-msg "system:dnd")"#), description: "Do Not Disturb"),
                KeyMapping(input: "f7", action: .keystroke(key: "prev"), description: "Previous track"),
                KeyMapping(input: "f8", action: .keystroke(key: "pp"), description: "Play / Pause"),
                KeyMapping(input: "f9", action: .keystroke(key: "next"), description: "Next track"),
                KeyMapping(input: "f10", action: .keystroke(key: "mute"), description: "Mute"),
                KeyMapping(input: "f11", action: .keystroke(key: "vold"), description: "Volume down"),
                KeyMapping(input: "f12", action: .keystroke(key: "volu"), description: "Volume up")
            ]
        case .function:
            // Standard F-keys: F1-F12 pass through as-is
            [
                KeyMapping(input: "f1", action: .keystroke(key: "f1"), description: "F1"),
                KeyMapping(input: "f2", action: .keystroke(key: "f2"), description: "F2"),
                KeyMapping(input: "f3", action: .keystroke(key: "f3"), description: "F3"),
                KeyMapping(input: "f4", action: .keystroke(key: "f4"), description: "F4"),
                KeyMapping(input: "f5", action: .keystroke(key: "f5"), description: "F5"),
                KeyMapping(input: "f6", action: .keystroke(key: "f6"), description: "F6"),
                KeyMapping(input: "f7", action: .keystroke(key: "f7"), description: "F7"),
                KeyMapping(input: "f8", action: .keystroke(key: "f8"), description: "F8"),
                KeyMapping(input: "f9", action: .keystroke(key: "f9"), description: "F9"),
                KeyMapping(input: "f10", action: .keystroke(key: "f10"), description: "F10"),
                KeyMapping(input: "f11", action: .keystroke(key: "f11"), description: "F11"),
                KeyMapping(input: "f12", action: .keystroke(key: "f12"), description: "F12")
            ]
        }
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
                    action: .hyper,
                    description: "Tap: Hyper, Hold: Hyper",
                    behavior: .dualRole(
                        DualRoleBehavior(
                            tapAction: .hyper,
                            holdAction: .hyper,
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
            configuration: .tapHoldPicker(TapHoldPickerConfig(
                inputKey: "caps",
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
                        output: "hyper",
                        label: "✦ Hyper",
                        description: "Tap for Hyper (⌃⌥⇧⌘) - useful when hold is something else",
                        icon: "bolt.circle"
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
                ],
                selectedTapOutput: "hyper",
                selectedHoldOutput: "hyper"
            ))
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
                KeyMapping(input: "lsft rsft", action: .keystroke(key: "caps"), description: "Both Shifts → Caps Lock")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "shift",
            tags: ["caps lock", "shift", "backup", "chord"],
            configuration: .singleKeyPicker(SingleKeyPickerConfig(
                inputKey: "backup-caps",
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
            ))
        )
    }

    private var escapeRemap: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.escapeRemap,
            name: "Escape",
            summary: "Remap the Escape key",
            category: .productivity,
            mappings: [
                KeyMapping(input: "esc", action: .keystroke(key: "caps"), description: "Caps Lock")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "escape",
            tags: ["escape", "caps lock", "swap"],
            configuration: .singleKeyPicker(SingleKeyPickerConfig(
                inputKey: "esc",
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
            ))
        )
    }

    private var deleteRemap: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.deleteRemap,
            name: "Delete Enhancement",
            summary: "Leader + Delete for enhanced delete actions (regular Delete unchanged)",
            category: .productivity,
            mappings: [
                KeyMapping(input: "bspc", action: .keystroke(key: "del"), description: "Forward Delete")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "delete.left",
            tags: ["delete", "backspace", "forward delete", "leader"],
            targetLayer: .navigation,
            activationHint: "Hold Leader key, then press Delete",
            configuration: .singleKeyPicker(SingleKeyPickerConfig(
                inputKey: "bspc",
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
            ))
        )
    }

    private var homeRowMods: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "Tap for letters, hold for modifiers or layers",
            category: .productivity,
            mappings: [], // Generated from homeRowModsConfig
            isEnabled: false,
            isSystemDefault: false,
            icon: "keyboard",
            tags: ["home row", "modifiers", "productivity", "ergonomics"],
            configuration: .homeRowMods(HomeRowModsConfig())
        )
    }

    private var homeRowLayerToggles: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.homeRowLayerToggles,
            name: "Home Row Layer Toggles",
            summary: "Home row keys activate layers when held (tap=letter, hold=layer)",
            category: .productivity,
            mappings: [], // Generated from homeRowLayerTogglesConfig
            isEnabled: false,
            isSystemDefault: false,
            owningPackID: PackRegistry.vallackSystem.id,
            icon: "square.3.layers.3d",
            tags: ["home row", "layers", "productivity", "ergonomics"],
            configuration: .homeRowLayerToggles(HomeRowLayerTogglesConfig())
        )
    }

    private var chordGroups: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.chordGroups,
            name: "Chord Groups",
            summary: "Multi-key combinations (Ben Vallack style) for efficient navigation and editing",
            category: .productivity,
            mappings: [], // Generated from chordGroupsConfig
            isEnabled: false,
            isSystemDefault: false,
            icon: "keyboard.badge.ellipsis",
            tags: ["chords", "defchords", "ben vallack", "productivity", "combos"],
            configuration: .chordGroups(ChordGroupsConfig())
        )
    }

    private var sequences: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.sequences,
            name: "Sequences",
            summary: "Create multi-key sequences like 'Leader → w' to activate layers",
            category: .productivity,
            mappings: [],
            isEnabled: false,
            isSystemDefault: false,
            icon: "arrow.right.arrow.left.circle",
            tags: ["sequences", "defseq", "leader", "multi-key"],
            configuration: .sequences(SequencesConfig())
        )
    }

    // MARK: - Numpad Layer

    private var numpadLayer: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.numpadLayer,
            name: "Numpad",
            summary: "Right hand becomes a numpad. Hold activator key + use U/I/O, J/K/L, M/,/. for 7-8-9, 4-5-6, 1-2-3.",
            category: .layers,
            mappings: [
                // Right hand numpad (standard layout)
                KeyMapping(input: "u", action: .keystroke(key: "kp7"), description: "7"),
                KeyMapping(input: "i", action: .keystroke(key: "kp8"), description: "8"),
                KeyMapping(input: "o", action: .keystroke(key: "kp9"), description: "9"),
                KeyMapping(input: "j", action: .keystroke(key: "kp4"), description: "4"),
                KeyMapping(input: "k", action: .keystroke(key: "kp5"), description: "5"),
                KeyMapping(input: "l", action: .keystroke(key: "kp6"), description: "6"),
                KeyMapping(input: "m", action: .keystroke(key: "kp1"), description: "1"),
                KeyMapping(input: ",", action: .keystroke(key: "kp2"), description: "2"),
                KeyMapping(input: ".", action: .keystroke(key: "kp3"), description: "3"),
                KeyMapping(input: "n", action: .keystroke(key: "kp0"), description: "0"),
                KeyMapping(input: "/", action: .keystroke(key: "kp."), description: "."),
                // Left hand operators
                KeyMapping(input: "f", action: .keystroke(key: "kp+"), description: "+", sectionBreak: true),
                KeyMapping(input: "d", action: .keystroke(key: "kp-"), description: "−"),
                KeyMapping(input: "s", action: .keystroke(key: "kp*"), description: "×"),
                KeyMapping(input: "a", action: .keystroke(key: "kp/"), description: "÷"),
                KeyMapping(input: "g", action: .keystroke(key: "kprt"), description: "⏎")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "number.square",
            tags: ["numpad", "numbers", "data entry", "calculator"],
            targetLayer: .custom("num"),
            momentaryActivator: MomentaryActivator(
                input: ";",
                targetLayer: .custom("num"),
                sourceLayer: .navigation // Two-step: Leader → ; → numpad layer
            ),
            activationHint: "Leader → ; → numpad keys",
            configuration: .table
        )
    }

    // MARK: - Symbol Layer

    private var symbolLayer: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.symbolLayer,
            name: "Symbol",
            summary: "Quick access to programming symbols. Choose a layout optimized for your workflow.",
            category: .layers,
            mappings: [], // Generated from selected layer preset
            isEnabled: false,
            isSystemDefault: false,
            icon: "textformat.abc.dottedunderline",
            tags: ["symbols", "programming", "brackets", "operators"],
            targetLayer: .custom("sym"),
            momentaryActivator: MomentaryActivator(
                input: "s",
                targetLayer: .custom("sym"),
                sourceLayer: .navigation // Two-step: Leader → s → symbol layer
            ),
            activationHint: "Leader → s → symbol keys",
            configuration: .layerPresetPicker(LayerPresetPickerConfig(
                presets: symbolLayerPresets,
                selectedPresetId: "mirrored"
            ))
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
                    KeyMapping(input: "1", action: .keystroke(key: "S-1"), description: "!"),
                    KeyMapping(input: "2", action: .keystroke(key: "S-2"), description: "@"),
                    KeyMapping(input: "3", action: .keystroke(key: "S-3"), description: "#"),
                    KeyMapping(input: "4", action: .keystroke(key: "S-4"), description: "$"),
                    KeyMapping(input: "5", action: .keystroke(key: "S-5"), description: "%"),
                    KeyMapping(input: "6", action: .keystroke(key: "S-6"), description: "^"),
                    KeyMapping(input: "7", action: .keystroke(key: "S-7"), description: "&"),
                    KeyMapping(input: "8", action: .keystroke(key: "S-8"), description: "*"),
                    KeyMapping(input: "9", action: .keystroke(key: "S-9"), description: "("),
                    KeyMapping(input: "0", action: .keystroke(key: "S-0"), description: ")"),
                    // Home row - common operators
                    KeyMapping(input: "a", action: .keystroke(key: "S-grv"), description: "~", sectionBreak: true),
                    KeyMapping(input: "s", action: .keystroke(key: "grv"), description: "`"),
                    KeyMapping(input: "d", action: .keystroke(key: "min"), description: "-"),
                    KeyMapping(input: "f", action: .keystroke(key: "eql"), description: "="),
                    KeyMapping(input: "g", action: .keystroke(key: "S-eql"), description: "+"),
                    KeyMapping(input: "h", action: .keystroke(key: "["), description: "["),
                    KeyMapping(input: "j", action: .keystroke(key: "]"), description: "]"),
                    KeyMapping(input: "k", action: .keystroke(key: "S-["), description: "{"),
                    KeyMapping(input: "l", action: .keystroke(key: "S-]"), description: "}"),
                    KeyMapping(input: ";", action: .keystroke(key: "S-\\"), description: "|"),
                    // Bottom row - less common
                    KeyMapping(input: "z", action: .keystroke(key: "\\"), description: "\\", sectionBreak: true),
                    KeyMapping(input: "x", action: .keystroke(key: "S-min"), description: "_"),
                    KeyMapping(input: "c", action: .keystroke(key: "/"), description: "/"),
                    KeyMapping(input: "v", action: .keystroke(key: "S-/"), description: "?"),
                    KeyMapping(input: "b", action: .keystroke(key: "'"), description: "'"),
                    KeyMapping(input: "n", action: .keystroke(key: "S-'"), description: "\""),
                    KeyMapping(input: "m", action: .keystroke(key: "S-;"), description: ":"),
                    KeyMapping(input: ",", action: .keystroke(key: "S-,"), description: "<"),
                    KeyMapping(input: ".", action: .keystroke(key: "S-."), description: ">")
                ]
            ),
            LayerPreset(
                id: "paired",
                label: "Paired Brackets",
                description: "Opening brackets on left, closing on right. Visual symmetry.",
                icon: "curlybraces",
                mappings: [
                    // Left hand - opening brackets and operators
                    KeyMapping(input: "q", action: .keystroke(key: "S-grv"), description: "~"),
                    KeyMapping(input: "w", action: .keystroke(key: "S-1"), description: "!"),
                    KeyMapping(input: "e", action: .keystroke(key: "S-2"), description: "@"),
                    KeyMapping(input: "r", action: .keystroke(key: "S-3"), description: "#"),
                    KeyMapping(input: "t", action: .keystroke(key: "S-4"), description: "$"),
                    KeyMapping(input: "a", action: .keystroke(key: "S-["), description: "{", sectionBreak: true),
                    KeyMapping(input: "s", action: .keystroke(key: "S-9"), description: "("),
                    KeyMapping(input: "d", action: .keystroke(key: "["), description: "["),
                    KeyMapping(input: "f", action: .keystroke(key: "S-,"), description: "<"),
                    KeyMapping(input: "g", action: .keystroke(key: "min"), description: "-"),
                    KeyMapping(input: "z", action: .keystroke(key: "S-\\"), description: "|", sectionBreak: true),
                    KeyMapping(input: "x", action: .keystroke(key: "S-eql"), description: "+"),
                    KeyMapping(input: "c", action: .keystroke(key: "S-min"), description: "_"),
                    KeyMapping(input: "v", action: .keystroke(key: "/"), description: "/"),
                    KeyMapping(input: "b", action: .keystroke(key: "\\"), description: "\\"),
                    // Right hand - closing brackets and symbols
                    KeyMapping(input: "y", action: .keystroke(key: "S-5"), description: "%", sectionBreak: true),
                    KeyMapping(input: "u", action: .keystroke(key: "S-6"), description: "^"),
                    KeyMapping(input: "i", action: .keystroke(key: "S-7"), description: "&"),
                    KeyMapping(input: "o", action: .keystroke(key: "S-8"), description: "*"),
                    KeyMapping(input: "p", action: .keystroke(key: "grv"), description: "`"),
                    KeyMapping(input: "h", action: .keystroke(key: "eql"), description: "=", sectionBreak: true),
                    KeyMapping(input: "j", action: .keystroke(key: "S-."), description: ">"),
                    KeyMapping(input: "k", action: .keystroke(key: "]"), description: "]"),
                    KeyMapping(input: "l", action: .keystroke(key: "S-0"), description: ")"),
                    KeyMapping(input: ";", action: .keystroke(key: "S-]"), description: "}"),
                    KeyMapping(input: "n", action: .keystroke(key: "S-/"), description: "?", sectionBreak: true),
                    KeyMapping(input: "m", action: .keystroke(key: "S-;"), description: ":"),
                    KeyMapping(input: ",", action: .keystroke(key: ";"), description: ";"),
                    KeyMapping(input: ".", action: .keystroke(key: "'"), description: "'"),
                    KeyMapping(input: "/", action: .keystroke(key: "S-'"), description: "\"")
                ]
            ),
            LayerPreset(
                id: "programmer",
                label: "Programmer",
                description: "Common bigrams (→, !=, <=) as comfortable rolls. Optimized for coding.",
                icon: "chevron.left.forwardslash.chevron.right",
                mappings: [
                    // Top row - numbers as-is for easy access
                    KeyMapping(input: "q", action: .keystroke(key: "S-1"), description: "!"),
                    KeyMapping(input: "w", action: .keystroke(key: "S-2"), description: "@"),
                    KeyMapping(input: "e", action: .keystroke(key: "S-3"), description: "#"),
                    KeyMapping(input: "r", action: .keystroke(key: "S-4"), description: "$"),
                    KeyMapping(input: "t", action: .keystroke(key: "S-5"), description: "%"),
                    KeyMapping(input: "y", action: .keystroke(key: "S-6"), description: "^"),
                    KeyMapping(input: "u", action: .keystroke(key: "S-7"), description: "&"),
                    KeyMapping(input: "i", action: .keystroke(key: "S-8"), description: "*"),
                    KeyMapping(input: "o", action: .keystroke(key: "S-grv"), description: "~"),
                    KeyMapping(input: "p", action: .keystroke(key: "grv"), description: "`"),
                    // Home row - brackets optimized for -> <= != bigrams
                    KeyMapping(input: "a", action: .keystroke(key: "S-["), description: "{", sectionBreak: true),
                    KeyMapping(input: "s", action: .keystroke(key: "S-9"), description: "("),
                    KeyMapping(input: "d", action: .keystroke(key: "["), description: "["),
                    KeyMapping(input: "f", action: .keystroke(key: "S-,"), description: "<"),
                    KeyMapping(input: "g", action: .keystroke(key: "eql"), description: "="),
                    KeyMapping(input: "h", action: .keystroke(key: "min"), description: "-"),
                    KeyMapping(input: "j", action: .keystroke(key: "S-."), description: ">"),
                    KeyMapping(input: "k", action: .keystroke(key: "]"), description: "]"),
                    KeyMapping(input: "l", action: .keystroke(key: "S-0"), description: ")"),
                    KeyMapping(input: ";", action: .keystroke(key: "S-]"), description: "}"),
                    // Bottom row - less common symbols
                    KeyMapping(input: "z", action: .keystroke(key: "S-\\"), description: "|", sectionBreak: true),
                    KeyMapping(input: "x", action: .keystroke(key: "S-eql"), description: "+"),
                    KeyMapping(input: "c", action: .keystroke(key: "S-min"), description: "_"),
                    KeyMapping(input: "v", action: .keystroke(key: "S-/"), description: "?"),
                    KeyMapping(input: "b", action: .keystroke(key: "\\"), description: "\\"),
                    KeyMapping(input: "n", action: .keystroke(key: "/"), description: "/"),
                    KeyMapping(input: "m", action: .keystroke(key: "S-;"), description: ":"),
                    KeyMapping(input: ",", action: .keystroke(key: ";"), description: ";"),
                    KeyMapping(input: ".", action: .keystroke(key: "'"), description: "'"),
                    KeyMapping(input: "/", action: .keystroke(key: "S-'"), description: "\"")
                ]
            )
        ]
    }

    // MARK: - Function Layer

    private var funLayer: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.funLayer,
            name: "Function",
            summary: "F-keys on right hand (numpad grid), media controls on left hand.",
            category: .layers,
            mappings: [
                // Right hand F-keys (numpad grid layout)
                KeyMapping(input: "u", action: .keystroke(key: "f7"), description: "F7"),
                KeyMapping(input: "i", action: .keystroke(key: "f8"), description: "F8"),
                KeyMapping(input: "o", action: .keystroke(key: "f9"), description: "F9"),
                KeyMapping(input: "j", action: .keystroke(key: "f4"), description: "F4"),
                KeyMapping(input: "k", action: .keystroke(key: "f5"), description: "F5"),
                KeyMapping(input: "l", action: .keystroke(key: "f6"), description: "F6"),
                KeyMapping(input: "m", action: .keystroke(key: "f1"), description: "F1"),
                KeyMapping(input: ",", action: .keystroke(key: "f2"), description: "F2"),
                KeyMapping(input: ".", action: .keystroke(key: "f3"), description: "F3"),
                KeyMapping(input: "n", action: .keystroke(key: "f10"), description: "F10"),
                KeyMapping(input: "/", action: .keystroke(key: "f11"), description: "F11"),
                KeyMapping(input: ";", action: .keystroke(key: "f12"), description: "F12"),
                // Left hand media controls
                KeyMapping(input: "f", action: .keystroke(key: "pp"), description: "Play/Pause", sectionBreak: true),
                KeyMapping(input: "d", action: .keystroke(key: "prev"), description: "Previous"),
                KeyMapping(input: "s", action: .keystroke(key: "next"), description: "Next"),
                KeyMapping(input: "a", action: .keystroke(key: "mute"), description: "Mute"),
                KeyMapping(input: "g", action: .keystroke(key: "volu"), description: "Volume Up"),
                KeyMapping(input: "r", action: .keystroke(key: "vold"), description: "Volume Down"),
                KeyMapping(input: "v", action: .keystroke(key: "brup"), description: "Brightness Up"),
                KeyMapping(input: "c", action: .keystroke(key: "brdn"), description: "Brightness Down")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "f.cursive",
            tags: ["function", "f-keys", "media", "brightness"],
            targetLayer: .custom("fun"),
            momentaryActivator: MomentaryActivator(
                input: "f",
                targetLayer: .custom("fun"),
                sourceLayer: .navigation // Two-step: Leader → f → fun layer
            ),
            activationHint: "Leader → f → function keys",
            configuration: .table
        )
    }

    // MARK: - Auto Shift Symbols

    private var autoShiftSymbols: RuleCollection {
        let config = AutoShiftSymbolsConfig()
        return RuleCollection(
            id: RuleCollectionIdentifier.autoShiftSymbols,
            name: "Auto Shift Symbols",
            summary: "Hold symbol keys slightly longer for shifted output",
            category: .experimental,
            mappings: [],
            isEnabled: false,
            icon: "arrow.up.square",
            tags: ["auto-shift", "symbols", "experimental"],
            targetLayer: .base,
            activationHint: "\(config.enabledKeys.count) keys \u{00B7} \(config.timeoutMs)ms hold",
            configuration: .autoShiftSymbols(config)
        )
    }

    // MARK: - Key Repeat Control

    private var keyRepeatControl: RuleCollection {
        let config = KeyRepeatControlConfig()
        return RuleCollection(
            id: RuleCollectionIdentifier.keyRepeatControl,
            name: "Fast Navigation",
            summary: "Arrow keys and delete repeat 3× faster. Regular keys stay steady.",
            category: .system,
            mappings: [],
            isEnabled: true,
            isSystemDefault: true,
            icon: "hare",
            tags: ["fast", "navigation", "arrows", "repeat", "speed"],
            configuration: .keyRepeatControl(config)
        )
    }

    // MARK: - Home Row Arrows

    private var homeRowArrows: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.homeRowArrows,
            name: "Home Row Arrows",
            summary: "Hold F for arrow keys under your right hand. Tap F normally. Your fingers never leave the home row.",
            category: .navigation,
            mappings: [
                // Inverted-T layout (default): I=up, J=left, K=down, L=right
                KeyMapping(input: "i", action: .keystroke(key: "up"), description: "↑", sectionLabel: "Arrows"),
                KeyMapping(input: "j", action: .keystroke(key: "left"), description: "←"),
                KeyMapping(input: "k", action: .keystroke(key: "down"), description: "↓"),
                KeyMapping(input: "l", action: .keystroke(key: "right"), description: "→"),
                // Extended navigation
                KeyMapping(input: "h", action: .keystroke(key: "home"), description: "Home", sectionBreak: true, sectionLabel: "Extended"),
                KeyMapping(input: ";", action: .keystroke(key: "end"), description: "End"),
                KeyMapping(input: "u", action: .keystroke(key: "pgup"), description: "Page Up"),
                KeyMapping(input: "o", action: .keystroke(key: "pgdn"), description: "Page Down"),
            ],
            isEnabled: true,
            isSystemDefault: true,
            icon: "arrow.up.and.down.and.arrow.left.and.right",
            tags: ["arrows", "navigation", "home row", "inverted-t", "beginner"],
            targetLayer: .custom("home-arrows"),
            momentaryActivator: MomentaryActivator(
                input: "f",
                targetLayer: .custom("home-arrows"),
                sourceLayer: .base
            ),
            activationHint: "Hold F for arrow keys",
            configuration: .table
        )
    }

    // MARK: - Vallack Navigation

    private var vallackNavigation: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.vallackNavigation,
            name: "Ben Vallack Nav",
            summary: "Hold F or J for arrows, clipboard, tab switching, and line navigation — fingers never leave the home row.",
            category: .navigation,
            mappings: [
                // Left hand — switching and editing
                KeyMapping(input: "q", action: .keystroke(key: "tab"), description: "tab", sectionLabel: "✋ Left hand"),
                KeyMapping(input: "w", action: .keystroke(key: "esc"), description: "esc"),
                KeyMapping(input: "e", action: .keystroke(key: "C-S-tab"), description: "◀tab"),
                KeyMapping(input: "r", action: .keystroke(key: "C-tab"), description: "tab▶"),
                KeyMapping(input: "a", action: .keystroke(key: "M-tab"), description: "⌘tab"),
                KeyMapping(input: "s", action: .keystroke(key: "home"), description: "home"),
                KeyMapping(input: "d", action: .keystroke(key: "end"), description: "end"),
                KeyMapping(input: "g", action: .keystroke(key: "C-M-S-4"), description: "Screenshot"),
                KeyMapping(input: "t", action: .keystroke(key: "M-["), description: "⌘["),
                KeyMapping(input: "v", action: .keystroke(key: "M-]"), description: "⌘]"),
                // Right hand — navigation
                KeyMapping(input: "h", action: .keystroke(key: "left"), description: "←", sectionBreak: true, sectionLabel: "🤚 Right hand"),
                KeyMapping(input: "j", action: .keystroke(key: "down"), description: "↓"),
                KeyMapping(input: "k", action: .keystroke(key: "up"), description: "↑"),
                KeyMapping(input: "l", action: .keystroke(key: "right"), description: "→"),
                KeyMapping(input: "u", action: .keystroke(key: "bspc"), description: "⌫"),
                KeyMapping(input: "i", action: .keystroke(key: "ret"), description: "↵"),
                KeyMapping(input: "y", action: .keystroke(key: "M-c"), description: "⌘C"),
                KeyMapping(input: ";", action: .keystroke(key: "M-v"), description: "⌘V")
            ],
            isEnabled: false,
            isSystemDefault: false,
            icon: "rectangle.stack.badge.play",
            tags: ["vallack", "navigation", "arrows", "home row", "system"],
            targetLayer: .custom("vallack-nav"),
            activationHint: "Hold F or J to enter navigation layer",
            configuration: .table
        )
    }

    // MARK: - Launcher

    private var launcher: RuleCollection {
        RuleCollection(
            id: RuleCollectionIdentifier.launcher,
            name: "Quick Launcher",
            summary: "Hold Hyper to quickly launch apps and websites with keyboard shortcuts.",
            category: .layers,
            mappings: [], // Mappings are derived from the launcherGrid configuration
            isEnabled: true,
            isSystemDefault: true,
            icon: "arrow.up.forward.app",
            tags: ["launcher", "apps", "websites", "productivity"],
            targetLayer: .custom("launcher"),
            momentaryActivator: MomentaryActivator(
                input: "hyper",
                targetLayer: .custom("launcher"),
                sourceLayer: .base
            ),
            activationHint: "Hold Hyper key",
            configuration: .launcherGrid(LauncherGridConfig.defaultConfig)
        )
    }

    // (Typing Sounds is configured in Settings; no collection entry.)
}
