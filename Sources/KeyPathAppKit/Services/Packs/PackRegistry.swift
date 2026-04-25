// M1 Gallery MVP — the hardcoded Starter Kit.
// See docs/design/sprint-1/starter-kit.md

import Foundation

/// Provides access to the M1 Starter Kit packs. Hardcoded in Swift; v2+ may
/// load from JSON or a manifest bundle.
public enum PackRegistry {
    /// All packs shipping in M1. Order matters — this is the display order in
    /// the Gallery view.
    public static let starterKit: [Pack] = [
        capsLockToEscape,
        homeRowMods,
        escapeRemap,
        deleteEnhancement,
        backupCapsLock,
        vimNavigation,
        windowSnapping,
        missionControl,
        autoShiftSymbols,
        numpadLayer,
        symbolLayer,
        funLayer,
        launcher,
        leaderKey
    ]

    /// Look up a pack by id. Returns nil if unknown.
    public static func pack(id: String) -> Pack? {
        starterKit.first(where: { $0.id == id })
    }

    /// Packs whose bindings target the given kanata key identifier (e.g.
    /// "caps", "d", "rmet"). Used by the Mapper inspector to surface
    /// contextual pack suggestions when the user selects an input.
    ///
    /// Normalizes common aliases (e.g. the overlay sends "capslock" while
    /// pack manifests use "caps"; "leftmeta" vs "lmet"; etc) so lookups
    /// succeed regardless of which spelling flavor the caller uses.
    public static func packsTargeting(kanataKey: String) -> [Pack] {
        let normalized = normalizeKanataKey(kanataKey)
        guard !normalized.isEmpty else { return [] }
        return starterKit.filter { pack in
            pack.affectedKeys.contains(where: { normalizeKanataKey($0) == normalized })
        }
    }

    /// Collapse the handful of long-form / short-form aliases used by
    /// different layers (overlay keymap, Kanata config, pack manifests)
    /// into a single canonical token.
    private static func normalizeKanataKey(_ key: String) -> String {
        let lower = key.lowercased()
        switch lower {
        case "capslock": return "caps"
        case "leftmeta": return "lmet"
        case "rightmeta": return "rmet"
        case "leftshift": return "lsft"
        case "rightshift": return "rsft"
        case "leftalt": return "lalt"
        case "rightalt": return "ralt"
        case "leftctrl": return "lctl"
        case "rightctrl": return "rctl"
        default: return lower
        }
    }

    // MARK: - Pack 1: Caps Lock → Escape

    public static let capsLockToEscape = Pack(
        id: "com.keypath.pack.caps-lock-to-escape",
        version: "1.0.0",
        name: "Caps Lock Remap",
        tagline: "Make Caps Lock actually useful with tap and hold actions",
        shortDescription:
            "Caps Lock is prime real estate in the corner — almost nobody uses it. Put it to work: tap it for a quick action like Escape, hold it for Hyper (⌃⌥⇧⌘), a modifier no app collides with. Pick your tap and hold below.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "capslock",
        iconSecondarySymbol: "escape",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(
                input: "caps",
                output: "esc",
                title: "Caps Lock → Escape"
            )
        ],
        associatedCollectionID: RuleCollectionIdentifier.capsLockRemap
    )

    // MARK: - Pack 2: Home Row Mods

    /// Mirrors the Rules tab's "Home Row Mods" collection: name, summary,
    /// and default seed bindings. When this pack is installed, Pack Detail
    /// delegates to the Home Row Mods UX the Rules tab uses.
    public static let homeRowMods = Pack(
        id: "com.keypath.pack.home-row-mods",
        version: "1.0.0",
        name: "Home Row Mods",
        tagline: "Tap for letters, hold for modifiers or layers",
        shortDescription:
            "Put your modifier keys under your strongest fingers. Tap A/S/D/F and J/K/L/; for the letter; hold for Shift / Control / Option / Command so shortcuts happen without leaving the home row.",
        longDescription: "",
        category: "Ergonomics",
        iconSymbol: "keyboard",
        iconSecondarySymbol: nil,
        quickSettings: [
            PackQuickSetting(
                id: "holdTimeout",
                label: "Hold timing",
                kind: .slider(
                    defaultValue: 180,
                    min: 120,
                    max: 300,
                    step: 20,
                    unitSuffix: " ms"
                )
            )
        ],
        bindings: [
            // CAGS left: A=Ctrl, S=Opt, D=Shift, F=Cmd
            PackBindingTemplate(input: "a", output: "a", holdOutput: "lctl",
                                title: "A · tap / Control · hold"),
            PackBindingTemplate(input: "s", output: "s", holdOutput: "lalt",
                                title: "S · tap / Option · hold"),
            PackBindingTemplate(input: "d", output: "d", holdOutput: "lsft",
                                title: "D · tap / Shift · hold"),
            PackBindingTemplate(input: "f", output: "f", holdOutput: "lmet",
                                title: "F · tap / Command · hold"),
            // CAGS right mirror: J=Cmd, K=Shift, L=Opt, ;=Ctrl
            PackBindingTemplate(input: "j", output: "j", holdOutput: "rmet",
                                title: "J · tap / Command · hold"),
            PackBindingTemplate(input: "k", output: "k", holdOutput: "rsft",
                                title: "K · tap / Shift · hold"),
            PackBindingTemplate(input: "l", output: "l", holdOutput: "ralt",
                                title: "L · tap / Option · hold"),
            PackBindingTemplate(input: "scln", output: "scln", holdOutput: "rctl",
                                title: "; · tap / Control · hold")
        ],
        associatedCollectionID: RuleCollectionIdentifier.homeRowMods
    )

    // MARK: - Pack 3: Escape Remap

    /// Gallery wrapper around the Rules tab's "Escape" single-key picker
    /// collection. Install toggles the collection; edits flow through
    /// `updateCollectionOutput` to persist the user's preset selection.
    public static let escapeRemap = Pack(
        id: "com.keypath.pack.escape-remap",
        version: "1.0.0",
        name: "Escape Remap",
        tagline: "Remap the Escape key",
        shortDescription:
            "Escape sits awkwardly off in the corner. Turn it into something more useful: Caps Lock (pairs perfectly with Caps Lock → Escape), backtick, or Tab. Pick below.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "escape",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(input: "esc", output: "caps", title: "Escape Remap")
        ],
        associatedCollectionID: RuleCollectionIdentifier.escapeRemap
    )

    // MARK: - Pack 4: Delete Enhancement

    public static let deleteEnhancement = Pack(
        id: "com.keypath.pack.delete-enhancement",
        version: "1.0.0",
        name: "Delete Enhancement",
        tagline: "Leader + Delete for enhanced delete actions",
        shortDescription:
            "Regular Delete stays as-is. Hold the Leader key and press Delete to get a different action: forward delete, delete word, or delete to line start. Pick which below. Requires a Leader pack on (Vim Navigation, KindaVim, or Neovim Terminal) for Space to activate the nav layer.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "delete.left",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(input: "bspc", output: "del", title: "Delete Enhancement")
        ],
        associatedCollectionID: RuleCollectionIdentifier.deleteRemap
    )

    // MARK: - Pack 5: Backup Caps Lock

    public static let backupCapsLock = Pack(
        id: "com.keypath.pack.backup-caps-lock",
        version: "1.0.0",
        name: "Backup Caps Lock",
        tagline: "Alternative way to access Caps Lock",
        shortDescription:
            "If Caps Lock Remap turns your Caps Lock into something else, you can still get Caps Lock back via a chord. Pick the one that feels natural.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "shift",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(input: "lsft-rsft", output: "caps", title: "Backup Caps Lock")
        ],
        associatedCollectionID: RuleCollectionIdentifier.backupCapsLock
    )

    // MARK: - Pack 6: Vim Navigation

    /// Collection-backed pack over `vimNavigation`. Activated by holding Space
    /// (the collection's momentary activator) to enter the navigation layer;
    /// inside that layer, hjkl become arrows, y/p are copy/paste, u is undo,
    /// etc. The pack ships with no explicit bindings — Pack Detail reads the
    /// mapping table from the associated collection so there's a single source
    /// of truth if the collection is updated.
    public static let vimNavigation = Pack(
        id: "com.keypath.pack.vim-navigation",
        version: "1.0.0",
        name: "Vim Navigation",
        tagline: "Hold Space for hjkl arrows and Vim motions",
        shortDescription:
            "Hold Space to enter Vim mode. h/j/k/l become arrow keys, y/p are copy/paste, u is undo, / is find. Release Space to go back to normal typing.",
        longDescription: "",
        category: "Navigation",
        iconSymbol: "arrow.up.and.down.and.arrow.left.and.right",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.vimNavigation
    )

    // MARK: - Pack 7: Window Snapping

    /// Collection-backed pack over `windowSnapping`. Entered as a nested
    /// layer — Leader → w takes you to the window layer, then action keys
    /// (l/r for halves, u/i/j/k for corners, [/] for displays, ,/. for
    /// Spaces) fire Accessibility-driven window moves.
    ///
    /// **Runtime dependency:** window moves require Accessibility API
    /// access. If the user has not granted it, pressing the action keys
    /// will parse but do nothing — kanata emits a `push-msg` that KeyPath
    /// intercepts; no AX access means no window ever moves. Surfacing a
    /// permission-check UI at install time is tracked as follow-up work
    /// (see docs/gallery/pack-migration-plan.md Tier-3 notes).
    public static let windowSnapping = Pack(
        id: "com.keypath.pack.window-snapping",
        version: "1.0.0",
        name: "Window Snapping",
        tagline: "Snap, move, and tile windows with Leader → w",
        shortDescription:
            "Hold Space, press W, then: L/R for left/right halves, M to maximize, U/I/J/K for corners, [ ] for displays, , . for Spaces, Z to undo. Requires a Leader pack (Vim Navigation, KindaVim, or Neovim Terminal) for Space to activate the nav layer, and Accessibility access (macOS will prompt on first use).",
        longDescription: "",
        category: "Navigation",
        iconSymbol: "rectangle.split.2x2",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.windowSnapping
    )

    // MARK: - Pack 8: Mission Control

    /// Collection-backed pack over `missionControl`. Leader (Space) held,
    /// then a single letter fires the system's Mission Control, Exposé,
    /// Desktop, and Notification Center actions. One-hand, no reach —
    /// consistent with the rest of the Gallery's Leader-based packs.
    public static let missionControl = Pack(
        id: "com.keypath.pack.mission-control",
        version: "1.0.0",
        name: "Mission Control",
        tagline: "Leader + single key for Exposé, Desktops, Notifications",
        shortDescription:
            "Hold Space, then: M = Mission Control, Q = App Exposé, T = Show Desktop, C = Notification Center, , / . for previous / next Desktop. Requires a Leader pack on (Vim Navigation, KindaVim, or Neovim Terminal) for Space to activate the nav layer.",
        longDescription: "",
        category: "Navigation",
        iconSymbol: "rectangle.3.group",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.missionControl
    )

    // MARK: - Pack 9: Auto Shift Symbols

    /// Collection-backed pack over `autoShiftSymbols`. Tap a symbol key
    /// normally; hold it slightly longer (~180ms) to get the shifted
    /// variant — no Shift reach needed. Tap hyphen for `-`; hold for `_`.
    /// Tap apostrophe for `'`; hold for `"`. Etc.
    ///
    /// Bindings here are illustrative: the kanata config is generated
    /// from the collection's `AutoShiftSymbolsConfig` at install, not
    /// from these templates. They exist so Pack Detail's fallback block
    /// can show users what they'll get without needing a dedicated editor.
    public static let autoShiftSymbols = Pack(
        id: "com.keypath.pack.auto-shift-symbols",
        version: "1.0.0",
        name: "Auto Shift Symbols",
        tagline: "Hold a symbol key for its shifted version",
        shortDescription:
            "Tap `-` for `-`, hold for `_`. Tap `'` for `'`, hold for `\"`. Tap `/` for `/`, hold for `?`. Works for all the usual shifted-symbol pairs — no more awkward Shift stretches.",
        longDescription: "",
        category: "Ergonomics",
        iconSymbol: "arrow.up.square",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(input: "-", output: "-", holdOutput: "S--", title: "- · tap / _ · hold"),
            PackBindingTemplate(input: "=", output: "=", holdOutput: "S-=", title: "= · tap / + · hold"),
            PackBindingTemplate(input: "'", output: "'", holdOutput: "S-'", title: "' · tap / \" · hold"),
            PackBindingTemplate(input: ";", output: ";", holdOutput: "S-;", title: "; · tap / : · hold"),
            PackBindingTemplate(input: ",", output: ",", holdOutput: "S-,", title: ", · tap / < · hold"),
            PackBindingTemplate(input: ".", output: ".", holdOutput: "S-.", title: ". · tap / > · hold"),
            PackBindingTemplate(input: "/", output: "/", holdOutput: "S-/", title: "/ · tap / ? · hold")
        ],
        associatedCollectionID: RuleCollectionIdentifier.autoShiftSymbols
    )

    // MARK: - Pack 10: Numpad Layer

    /// Collection-backed pack over `numpadLayer`. Activated via the two-step
    /// Leader → ; sequence, the right hand becomes a numpad (u/i/o → 7/8/9,
    /// j/k/l → 4/5/6, m/,/. → 1/2/3, n → 0). Left hand gets operators
    /// (f → +, d → −, s → ×, a → ÷, g → ⏎). Great for spreadsheets,
    /// calculators, and CSS pixel-counting without reaching for the number
    /// row or the physical numpad.
    public static let numpadLayer = Pack(
        id: "com.keypath.pack.numpad-layer",
        version: "1.0.0",
        name: "Numpad",
        tagline: "Turn your right hand into a numpad",
        shortDescription:
            "Hold Space, press `;`, then use u/i/o + j/k/l + m/,/. as a numpad. Left-hand keys become operators (+ − × ÷ ⏎). Release Space to go back to normal typing. Requires a Leader pack on (Vim Navigation, KindaVim, or Neovim Terminal) for Space to activate the nav layer.",
        longDescription: "",
        category: "Layers",
        iconSymbol: "number.square",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.numpadLayer
    )

    // MARK: - Pack 11: Symbol Layer

    /// Collection-backed pack over `symbolLayer`. Two-step activation: hold
    /// Space for nav, hold `s` to enter the sym layer. Inside the layer,
    /// the selected preset (default: Mirrored) rebinds keys to common
    /// programming symbols — the shifted number row in the same positions,
    /// plus brackets/operators clustered on the home row.
    ///
    /// Pack `bindings` are illustrative samples from the default Mirrored
    /// preset; the actual kanata config is generated from the collection's
    /// `LayerPresetPickerConfig.selectedPresetId` at install time. A
    /// dedicated layer-preset picker in Pack Detail is follow-up work.
    public static let symbolLayer = Pack(
        id: "com.keypath.pack.symbol-layer",
        version: "1.0.0",
        name: "Symbol",
        tagline: "Programming symbols under your home row",
        shortDescription:
            "Hold Space, hold `s`, then hit the number row for shifted symbols in the same positions (1→!, 2→@, 3→#…), home row for brackets/operators ([, ], {, }, -, =, +…). Picks up whichever preset is selected in Rules. Requires a Leader pack on (Vim Navigation, KindaVim, or Neovim Terminal) for Space to activate the nav layer.",
        longDescription: "",
        category: "Layers",
        iconSymbol: "textformat.abc.dottedunderline",
        quickSettings: [],
        bindings: [
            PackBindingTemplate(input: "1", output: "S-1", title: "1 → !"),
            PackBindingTemplate(input: "2", output: "S-2", title: "2 → @"),
            PackBindingTemplate(input: "3", output: "S-3", title: "3 → #"),
            PackBindingTemplate(input: "d", output: "min", title: "d → -"),
            PackBindingTemplate(input: "f", output: "eql", title: "f → ="),
            PackBindingTemplate(input: "h", output: "[", title: "h → ["),
            PackBindingTemplate(input: "j", output: "]", title: "j → ]"),
            PackBindingTemplate(input: "k", output: "S-[", title: "k → {"),
            PackBindingTemplate(input: "l", output: "S-]", title: "l → }")
        ],
        associatedCollectionID: RuleCollectionIdentifier.symbolLayer
    )

    // MARK: - Pack 12: Function / Media Layer

    /// Collection-backed pack over `funLayer`. Two-step activation:
    /// hold Space for nav, hold `f` to enter the fun layer. Right hand
    /// becomes a 3x4 F-key numpad (u/i/o = F7/F8/F9, j/k/l = F4/F5/F6,
    /// m/,/. = F1/F2/F3, n = F10, / = F11, ; = F12). Left hand becomes
    /// media/system controls (f = Play/Pause, d = Prev, s = Next, a =
    /// Mute, g = Vol Up, r = Vol Down, v = Brightness Up, c = Brightness
    /// Down).
    public static let funLayer = Pack(
        id: "com.keypath.pack.fun-layer",
        version: "1.0.0",
        name: "Function",
        tagline: "Right hand becomes F-keys, left hand is media/brightness",
        shortDescription:
            "Hold Space, press `f`, then: right hand (u/i/o + j/k/l + m/,/.) is an F-key grid; left hand is media — play/pause, prev/next, mute, volume, brightness. Everything reachable from home position. Requires a Leader pack on (Vim Navigation, KindaVim, or Neovim Terminal) for Space to activate the nav layer.",
        longDescription: "",
        category: "Layers",
        iconSymbol: "f.cursive",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.funLayer
    )

    // MARK: - Pack 13: Quick Launcher

    /// Collection-backed pack over `launcher`. Hold the Hyper key to enter
    /// the launcher layer, then press a single key to launch an app or
    /// open a URL. Pack Detail embeds the same `LauncherCollectionView`
    /// the Rules tab uses so you can pick keys, drop apps, and switch
    /// between Hold-Hyper and Leader→L activation right from the pack.
    ///
    /// Unlike the nav-layer packs (Numpad, Symbol, Fun, Mission Control,
    /// etc.), Launcher activates directly from the base layer via Hyper —
    /// so it works standalone without a Leader pack on.
    public static let launcher = Pack(
        id: "com.keypath.pack.quick-launcher",
        version: "1.0.0",
        name: "Quick Launcher",
        tagline: "Hold Hyper, press a key to launch an app or website",
        shortDescription:
            "Map any key to launch an app (Slack, Cursor, Figma) or open a URL (gmail.com, calendar.google.com). Tap Hyper + the key. Add and edit mappings inline — drag an app onto a key, or pick from your browser history.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "arrow.up.forward.app",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.launcher
    )

    // MARK: - Pack 14: Leader Key

    /// Collection-backed pack over `leaderKey`. Picks which physical key
    /// activates the navigation layer (the "Leader") for every other
    /// nav-based pack you have on — Vim Navigation, Window Snapping,
    /// Mission Control, Numpad, Symbol, Function, Delete Enhancement.
    /// Default is Space; alternatives are Caps Lock, Tab, or Backtick.
    ///
    /// This pack doesn't add new mappings of its own — it changes a global
    /// preference that the config generator reads when it emits the nav
    /// activator. Touching it from Pack Detail routes through
    /// `updateCollectionOutput` which special-cases the Leader Key
    /// collection and writes through to `LeaderKeyPreference`.
    public static let leaderKey = Pack(
        id: "com.keypath.pack.leader-key",
        version: "1.0.0",
        name: "Leader Key",
        tagline: "Pick which key activates the navigation layer",
        shortDescription:
            "Default is Space — but if your thumb's already busy, swap to Caps Lock (the most common alternative), Tab, or Backtick. The change applies everywhere: Vim Nav, Mission Control, Numpad, Symbol, Function, Window Snapping, and Delete Enhancement all use whatever you pick.",
        longDescription: "",
        category: "Productivity",
        iconSymbol: "hand.point.up.left",
        quickSettings: [],
        bindings: [],
        associatedCollectionID: RuleCollectionIdentifier.leaderKey
    )
}
